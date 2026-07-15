/*
 * External split-screen input simulator for macOS.
 *
 * This intentionally lives outside the game. It posts keyboard and mouse events
 * through Quartz so OpenJK receives them through the same OS event path as
 * normal keyboard and mouse input.
 *
 * Controller/gamepad simulation uses IOHIDUserDevice, which is a real virtual
 * HID device outside OpenJK. macOS requires the virtual HID entitlement for
 * that backend to activate successfully.
 */

#include <ApplicationServices/ApplicationServices.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/hidsystem/IOHIDUserDevice.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct key_map_s {
	const char *name;
	CGKeyCode code;
} key_map_t;

static const key_map_t key_map[] = {
	{ "a", 0 }, { "s", 1 }, { "d", 2 }, { "f", 3 }, { "h", 4 }, { "g", 5 },
	{ "z", 6 }, { "x", 7 }, { "c", 8 }, { "v", 9 }, { "b", 11 }, { "q", 12 },
	{ "w", 13 }, { "e", 14 }, { "r", 15 }, { "y", 16 }, { "t", 17 },
	{ "1", 18 }, { "2", 19 }, { "3", 20 }, { "4", 21 }, { "6", 22 },
	{ "5", 23 }, { "=", 24 }, { "9", 25 }, { "7", 26 }, { "-", 27 },
	{ "8", 28 }, { "0", 29 }, { "]", 30 }, { "o", 31 }, { "u", 32 },
	{ "[", 33 }, { "i", 34 }, { "p", 35 }, { "l", 37 }, { "j", 38 },
	{ "'", 39 }, { "k", 40 }, { ";", 41 }, { "\\", 42 }, { ",", 43 },
	{ "/", 44 }, { "n", 45 }, { "m", 46 }, { ".", 47 }, { "`", 50 },
	{ "space", 49 }, { "tab", 48 }, { "enter", 36 }, { "return", 36 },
	{ "escape", 53 }, { "esc", 53 }, { "backspace", 51 }, { "delete", 51 },
	{ "left", 123 }, { "right", 124 }, { "down", 125 }, { "up", 126 },
	{ "shift", 56 }, { "ctrl", 59 }, { "control", 59 }, { "alt", 58 },
	{ "option", 58 }, { "cmd", 55 }, { "command", 55 },
};

static void usage( const char *argv0 )
{
	fprintf( stderr,
		"usage: %s <commands...>\n"
		"\n"
		"commands:\n"
		"  check-permission\n"
		"  request-permission\n"
		"  wait <ms>\n"
		"  key <name> <down|up|tap>\n"
		"  mouse <dx> <dy>\n"
		"  click <left|right>\n"
		"  gamepad-demo <ms>   # create an external virtual HID gamepad and send a short input sequence\n"
		"\n"
		"example:\n"
		"  %s wait 1000 key w down wait 250 key w up mouse 30 0 click left\n",
		argv0, argv0 );
}

static int streq( const char *a, const char *b )
{
	return strcmp( a, b ) == 0;
}

static int lookup_key( const char *name, CGKeyCode *out )
{
	size_t i;
	char lower[64];
	size_t len = strlen( name );

	if ( len >= sizeof( lower ) ) {
		return 0;
	}
	for ( i = 0; i <= len; i++ ) {
		lower[i] = (char)tolower( (unsigned char)name[i] );
	}

	for ( i = 0; i < sizeof( key_map ) / sizeof( key_map[0] ); i++ ) {
		if ( streq( lower, key_map[i].name ) ) {
			*out = key_map[i].code;
			return 1;
		}
	}
	return 0;
}

static int trusted( int prompt )
{
	const void *keys[] = { kAXTrustedCheckOptionPrompt };
	const void *values[] = { prompt ? kCFBooleanTrue : kCFBooleanFalse };
	CFDictionaryRef options = CFDictionaryCreate( NULL, keys, values, 1, NULL, NULL );
	Boolean ok = AXIsProcessTrustedWithOptions( options );
	CFRelease( options );
	return ok ? 1 : 0;
}

static void cfset_int( CFMutableDictionaryRef dict, CFStringRef key, int value )
{
	CFNumberRef number = CFNumberCreate( NULL, kCFNumberIntType, &value );
	CFDictionarySetValue( dict, key, number );
	CFRelease( number );
}

static void post_key( CGKeyCode key, int down )
{
	CGEventRef event = CGEventCreateKeyboardEvent( NULL, key, down ? true : false );
	CGEventPost( kCGHIDEventTap, event );
	CFRelease( event );
}

static void post_mouse_move( int dx, int dy )
{
	CGEventRef current = CGEventCreate( NULL );
	CGPoint point = CGEventGetLocation( current );
	CFRelease( current );

	point.x += dx;
	point.y += dy;

	CGEventRef event = CGEventCreateMouseEvent( NULL, kCGEventMouseMoved, point, 0 );
	CGEventPost( kCGHIDEventTap, event );
	CFRelease( event );
}

static void post_click( const char *button )
{
	CGMouseButton cg_button = kCGMouseButtonLeft;
	CGEventType down_type = kCGEventLeftMouseDown;
	CGEventType up_type = kCGEventLeftMouseUp;
	CGEventRef current;
	CGPoint point;
	CGEventRef event;

	if ( streq( button, "right" ) ) {
		cg_button = kCGMouseButtonRight;
		down_type = kCGEventRightMouseDown;
		up_type = kCGEventRightMouseUp;
	} else if ( !streq( button, "left" ) ) {
		fprintf( stderr, "unknown mouse button: %s\n", button );
		exit( 2 );
	}

	current = CGEventCreate( NULL );
	point = CGEventGetLocation( current );
	CFRelease( current );

	event = CGEventCreateMouseEvent( NULL, down_type, point, cg_button );
	CGEventPost( kCGHIDEventTap, event );
	CFRelease( event );

	usleep( 20000 );

	event = CGEventCreateMouseEvent( NULL, up_type, point, cg_button );
	CGEventPost( kCGHIDEventTap, event );
	CFRelease( event );
}

static IOHIDUserDeviceRef create_virtual_gamepad( void )
{
	static const uint8_t descriptor[] = {
		0x05, 0x01,       /* Usage Page (Generic Desktop) */
		0x09, 0x05,       /* Usage (Game Pad) */
		0xA1, 0x01,       /* Collection (Application) */
		0x85, 0x01,       /*   Report ID (1) */
		0x05, 0x09,       /*   Usage Page (Button) */
		0x19, 0x01,       /*   Usage Minimum (1) */
		0x29, 0x10,       /*   Usage Maximum (16) */
		0x15, 0x00,       /*   Logical Minimum (0) */
		0x25, 0x01,       /*   Logical Maximum (1) */
		0x75, 0x01,       /*   Report Size (1) */
		0x95, 0x10,       /*   Report Count (16) */
		0x81, 0x02,       /*   Input (Data, Variable, Absolute) */
		0x05, 0x01,       /*   Usage Page (Generic Desktop) */
		0x09, 0x30,       /*   Usage (X) */
		0x09, 0x31,       /*   Usage (Y) */
		0x09, 0x32,       /*   Usage (Z) */
		0x09, 0x35,       /*   Usage (Rz) */
		0x15, 0x81,       /*   Logical Minimum (-127) */
		0x25, 0x7F,       /*   Logical Maximum (127) */
		0x75, 0x08,       /*   Report Size (8) */
		0x95, 0x04,       /*   Report Count (4) */
		0x81, 0x02,       /*   Input (Data, Variable, Absolute) */
		0xC0              /* End Collection */
	};
	CFMutableDictionaryRef properties;
	CFDataRef report_descriptor;
	IOHIDUserDeviceRef device;
	dispatch_queue_t queue;

	properties = CFDictionaryCreateMutable( NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks );
	report_descriptor = CFDataCreate( NULL, descriptor, sizeof( descriptor ) );
	CFDictionarySetValue( properties, CFSTR( kIOHIDReportDescriptorKey ), report_descriptor );
	CFDictionarySetValue( properties, CFSTR( kIOHIDProductKey ), CFSTR( "OpenJK QA Virtual Gamepad" ) );
	cfset_int( properties, CFSTR( kIOHIDVendorIDKey ), 0x1209 );
	cfset_int( properties, CFSTR( kIOHIDProductIDKey ), 0x4A4B );
	cfset_int( properties, CFSTR( kIOHIDPrimaryUsagePageKey ), 0x01 );
	cfset_int( properties, CFSTR( kIOHIDPrimaryUsageKey ), 0x05 );
	cfset_int( properties, CFSTR( kIOHIDMaxInputReportSizeKey ), 7 );

	device = IOHIDUserDeviceCreateWithProperties( NULL, properties, 0 );
	CFRelease( report_descriptor );
	CFRelease( properties );
	if ( !device ) {
		return NULL;
	}

	queue = dispatch_queue_create( "openjk.qa.virtual-gamepad", DISPATCH_QUEUE_SERIAL );
	IOHIDUserDeviceSetDispatchQueue( device, queue );
	IOHIDUserDeviceActivate( device );
	dispatch_release( queue );
	return device;
}

static void send_gamepad_report( IOHIDUserDeviceRef device, uint16_t buttons, int8_t x, int8_t y, int8_t z, int8_t rz )
{
	uint8_t report[7];
	report[0] = 1;
	report[1] = (uint8_t)( buttons & 0xff );
	report[2] = (uint8_t)( ( buttons >> 8 ) & 0xff );
	report[3] = (uint8_t)x;
	report[4] = (uint8_t)y;
	report[5] = (uint8_t)z;
	report[6] = (uint8_t)rz;
	IOHIDUserDeviceHandleReportWithTimeStamp( device, mach_absolute_time(), report, sizeof( report ) );
}

static int gamepad_demo( int duration_ms )
{
	IOHIDUserDeviceRef device = create_virtual_gamepad();

	if ( !device ) {
		fprintf( stderr,
			"Could not create IOHIDUserDevice virtual gamepad. macOS requires the "
			"com.apple.developer.hid.virtual.device entitlement for this backend.\n" );
		return 4;
	}

	printf( "Created virtual HID gamepad. Keep this process running before launching OpenJK for SDL enumeration.\n" );
	send_gamepad_report( device, 0, 0, 0, 0, 0 );
	usleep( 500000 );
	send_gamepad_report( device, 0, 0, 127, 0, 0 );
	usleep( 250000 );
	send_gamepad_report( device, 0, 0, 0, 0, 0 );
	send_gamepad_report( device, 1, 0, 0, 0, 0 );
	usleep( 100000 );
	send_gamepad_report( device, 0, 0, 0, 0, 0 );

	if ( duration_ms > 0 ) {
		usleep( (useconds_t)duration_ms * 1000 );
	}

	IOHIDUserDeviceCancel( device );
	CFRelease( device );
	return 0;
}

int main( int argc, char **argv )
{
	int i = 1;

	if ( argc < 2 ) {
		usage( argv[0] );
		return 2;
	}

	while ( i < argc ) {
		const char *cmd = argv[i++];

		if ( streq( cmd, "check-permission" ) ) {
			if ( !trusted( 0 ) ) {
				fprintf( stderr, "Accessibility permission is not granted for this process.\n" );
				return 3;
			}
			printf( "Accessibility permission granted.\n" );
			continue;
		}

		if ( streq( cmd, "request-permission" ) ) {
			if ( !trusted( 1 ) ) {
				fprintf( stderr, "Accessibility permission was requested but is not granted yet.\n" );
				return 3;
			}
			printf( "Accessibility permission granted.\n" );
			continue;
		}

		if ( streq( cmd, "wait" ) ) {
			if ( i >= argc ) {
				usage( argv[0] );
				return 2;
			}
			usleep( (useconds_t)( atoi( argv[i++] ) * 1000 ) );
			continue;
		}

		if ( streq( cmd, "key" ) ) {
			CGKeyCode key;
			const char *name;
			const char *action;

			if ( i + 1 >= argc ) {
				usage( argv[0] );
				return 2;
			}
			name = argv[i++];
			action = argv[i++];
			if ( !lookup_key( name, &key ) ) {
				fprintf( stderr, "unknown key: %s\n", name );
				return 2;
			}
			if ( streq( action, "down" ) ) {
				post_key( key, 1 );
			} else if ( streq( action, "up" ) ) {
				post_key( key, 0 );
			} else if ( streq( action, "tap" ) ) {
				post_key( key, 1 );
				usleep( 20000 );
				post_key( key, 0 );
			} else {
				fprintf( stderr, "unknown key action: %s\n", action );
				return 2;
			}
			continue;
		}

		if ( streq( cmd, "mouse" ) ) {
			int dx;
			int dy;
			if ( i + 1 >= argc ) {
				usage( argv[0] );
				return 2;
			}
			dx = atoi( argv[i++] );
			dy = atoi( argv[i++] );
			post_mouse_move( dx, dy );
			continue;
		}

		if ( streq( cmd, "click" ) ) {
			if ( i >= argc ) {
				usage( argv[0] );
				return 2;
			}
			post_click( argv[i++] );
			continue;
		}

		if ( streq( cmd, "gamepad-demo" ) ) {
			int duration_ms;
			if ( i >= argc ) {
				usage( argv[0] );
				return 2;
			}
			duration_ms = atoi( argv[i++] );
			return gamepad_demo( duration_ms );
		}

		fprintf( stderr, "unknown command: %s\n", cmd );
		usage( argv[0] );
		return 2;
	}

	return 0;
}
