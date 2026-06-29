import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_calendar/device_calendar.dart' as device_calendar;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'mcp_models.dart';

enum LocalToolPermission { none, location, contacts, calendar, reminders }

class LocalToolDefinition {
  final String id;
  final String groupId;
  final String groupName;
  final String name;
  final String displayName;
  final String description;
  final Map<String, dynamic> inputSchema;
  final LocalToolPermission permission;
  final bool defaultEnabled;
  final bool Function() isSupported;

  const LocalToolDefinition({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.name,
    required this.displayName,
    required this.description,
    required this.inputSchema,
    this.permission = LocalToolPermission.none,
    this.defaultEnabled = false,
    required this.isSupported,
  });

  McpTool toMcpTool() {
    return McpTool(
      name: name,
      description: description,
      inputSchema: inputSchema,
      annotations: const {
        'audience': ['llm'],
        'local': true,
      },
    );
  }
}

class LocalToolResult {
  final String toolId;
  final String toolName;
  final String result;

  const LocalToolResult({
    required this.toolId,
    required this.toolName,
    required this.result,
  });

  Map<String, dynamic> toToolResult() {
    return {'toolId': toolId, 'toolName': toolName, 'result': result};
  }
}

class LocalToolService {
  static const String timeToolId = 'time';
  static const MethodChannel _remindersChannel = MethodChannel(
    'com.kaiserapps.joey/local_reminders',
  );
  static const MethodChannel _alarmChannel = MethodChannel(
    'com.kaiserapps.joey/local_alarm',
  );

  static bool _timeZonesInitialized = false;

  final Set<String> enabledToolIds;
  final device_calendar.DeviceCalendarPlugin _calendarPlugin;

  LocalToolService({
    required Set<String> enabledToolIds,
    device_calendar.DeviceCalendarPlugin? calendarPlugin,
  }) : enabledToolIds = Set.unmodifiable(enabledToolIds),
       _calendarPlugin =
           calendarPlugin ?? device_calendar.DeviceCalendarPlugin();

  static List<LocalToolDefinition> get allTools => _tools;

  static Set<String> get defaultToolIds => _tools
      .where((tool) => tool.defaultEnabled && tool.isSupported())
      .map((tool) => tool.id)
      .toSet();

  List<McpTool> get enabledTools => _tools
      .where((tool) => enabledToolIds.contains(tool.id) && tool.isSupported())
      .map((tool) => tool.toMcpTool())
      .toList();

  List<LocalToolDefinition> get enabledDefinitions => _tools
      .where((tool) => enabledToolIds.contains(tool.id) && tool.isSupported())
      .toList();

  bool canExecute(String toolName) {
    return _tools.any(
      (tool) =>
          tool.name == toolName &&
          tool.isSupported() &&
          enabledToolIds.contains(tool.id),
    );
  }

  static LocalToolDefinition? definitionById(String id) {
    return _tools.cast<LocalToolDefinition?>().firstWhere(
      (tool) => tool!.id == id,
      orElse: () => null,
    );
  }

  static Future<bool> requestPermissionForTool(String toolId) async {
    final definition = definitionById(toolId);
    if (definition == null || !definition.isSupported()) return false;

    switch (definition.permission) {
      case LocalToolPermission.none:
        return true;
      case LocalToolPermission.location:
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return false;
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        return permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;
      case LocalToolPermission.contacts:
        final status = await FlutterContacts.permissions.request(
          PermissionType.readWrite,
        );
        return status == PermissionStatus.granted ||
            status == PermissionStatus.limited;
      case LocalToolPermission.calendar:
        final plugin = device_calendar.DeviceCalendarPlugin();
        final result = await plugin.requestPermissions();
        return result.isSuccess && result.data == true;
      case LocalToolPermission.reminders:
        if (!isIos) return false;
        final granted = await _remindersChannel.invokeMethod<bool>(
          'requestPermission',
        );
        return granted == true;
    }
  }

  static Future<String> permissionStatusForTool(String toolId) async {
    final definition = definitionById(toolId);
    if (definition == null) return 'Unknown tool';
    if (!definition.isSupported()) return 'Unsupported on this platform';

    switch (definition.permission) {
      case LocalToolPermission.none:
        return 'No permission required';
      case LocalToolPermission.location:
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return 'Location services disabled';
        final permission = await Geolocator.checkPermission();
        return switch (permission) {
          LocationPermission.always ||
          LocationPermission.whileInUse => 'Granted',
          LocationPermission.denied => 'Not granted',
          LocationPermission.deniedForever => 'Denied permanently',
          LocationPermission.unableToDetermine => 'Unable to determine',
        };
      case LocalToolPermission.contacts:
        final status = await FlutterContacts.permissions.check(
          PermissionType.readWrite,
        );
        return switch (status) {
          PermissionStatus.granted => 'Granted',
          PermissionStatus.limited => 'Limited',
          PermissionStatus.denied ||
          PermissionStatus.notDetermined => 'Not granted',
          PermissionStatus.permanentlyDenied => 'Denied permanently',
          PermissionStatus.restricted => 'Restricted',
        };
      case LocalToolPermission.calendar:
        final plugin = device_calendar.DeviceCalendarPlugin();
        final result = await plugin.hasPermissions();
        if (!result.isSuccess) return 'Unable to determine';
        return result.data == true ? 'Granted' : 'Not granted';
      case LocalToolPermission.reminders:
        if (!isIos) return 'Unsupported on this platform';
        final granted = await _remindersChannel.invokeMethod<bool>(
          'checkPermission',
        );
        return granted == true ? 'Granted' : 'Not granted';
    }
  }

  Future<LocalToolResult> executeToolCall(Map<String, dynamic> toolCall) async {
    final toolId = toolCall['id'] as String;
    final function = toolCall['function'] as Map<String, dynamic>;
    final toolName = function['name'] as String;
    final rawArgs = function['arguments'];
    final args = rawArgs is String
        ? Map<String, dynamic>.from(jsonDecode(rawArgs) as Map)
        : Map<String, dynamic>.from(rawArgs as Map);

    final result = switch (toolName) {
      'local_get_time' => await _getTime(args),
      'local_get_location' => await _getLocation(),
      'local_search_contacts' => await _searchContacts(args),
      'local_get_contact' => await _getContact(args),
      'local_create_contact' => await _createContact(args),
      'local_update_contact' => await _updateContact(args),
      'local_delete_contact' => await _deleteContact(args),
      'local_compose_sms' => _composeSms(args),
      'local_call_phone_number' => _callPhoneNumber(args),
      'local_compose_email' => _composeEmail(args),
      'local_get_device_info' => await _getDeviceInfo(),
      'local_open_url' => _openUrl(args),
      'local_create_alarm' => await _createAlarm(args),
      'local_search_calendar_events' => await _searchCalendarEvents(args),
      'local_create_calendar_event' => await _createCalendarEvent(args),
      'local_update_calendar_event' => await _updateCalendarEvent(args),
      'local_delete_calendar_event' => await _deleteCalendarEvent(args),
      'local_search_reminders' => await _invokeReminderTool('search', args),
      'local_create_reminder' => await _invokeReminderTool('create', args),
      'local_update_reminder' => await _invokeReminderTool('update', args),
      'local_delete_reminder' => await _invokeReminderTool('delete', args),
      _ => 'Local tool not found: $toolName',
    };

    return LocalToolResult(toolId: toolId, toolName: toolName, result: result);
  }

  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  static bool get isIos => !kIsWeb && Platform.isIOS;

  static final List<LocalToolDefinition> _tools = [
    LocalToolDefinition(
      id: timeToolId,
      groupId: 'time',
      groupName: 'Time',
      name: 'local_get_time',
      displayName: 'Get time',
      defaultEnabled: true,
      isSupported: () => true,
      description:
          'Local-only tool. Gets the current date and time for the device timezone or a supplied IANA timezone such as "Australia/Sydney" or "America/New_York".',
      inputSchema: {
        'type': 'object',
        'properties': {
          'timezone': {
            'type': 'string',
            'description':
                'Optional IANA timezone. If omitted, uses the device timezone.',
          },
        },
      },
    ),
    LocalToolDefinition(
      id: 'location',
      groupId: 'location',
      groupName: 'Location',
      name: 'local_get_location',
      displayName: 'Get current location',
      permission: LocalToolPermission.location,
      isSupported: () => isMobile,
      description:
          'Local-only tool. Gets the device current foreground location after user permission.',
      inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    ),
    LocalToolDefinition(
      id: 'contacts_search',
      groupId: 'contacts',
      groupName: 'Contacts',
      name: 'local_search_contacts',
      displayName: 'Search contacts',
      permission: LocalToolPermission.contacts,
      isSupported: () => isMobile,
      description:
          'Local-only tool. Searches contacts on the device by display name, phone, or email.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'limit': {'type': 'integer', 'default': 10},
        },
        'required': ['query'],
      },
    ),
    LocalToolDefinition(
      id: 'contacts_manage',
      groupId: 'contacts',
      groupName: 'Contacts',
      name: 'local_get_contact',
      displayName: 'Get contact',
      permission: LocalToolPermission.contacts,
      isSupported: () => isMobile,
      description: 'Local-only tool. Retrieves full details for a contact ID.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
        },
        'required': ['id'],
      },
    ),
    LocalToolDefinition(
      id: 'contacts_create',
      groupId: 'contacts',
      groupName: 'Contacts',
      name: 'local_create_contact',
      displayName: 'Create contact',
      permission: LocalToolPermission.contacts,
      isSupported: () => isMobile,
      description: 'Local-only tool. Creates a contact on the device.',
      inputSchema: _contactMutationSchema(requiredName: true),
    ),
    LocalToolDefinition(
      id: 'contacts_update',
      groupId: 'contacts',
      groupName: 'Contacts',
      name: 'local_update_contact',
      displayName: 'Update contact',
      permission: LocalToolPermission.contacts,
      isSupported: () => isMobile,
      description:
          'Local-only tool. Updates a contact name, phone numbers, or email addresses on the device.',
      inputSchema: _contactMutationSchema(requireId: true),
    ),
    LocalToolDefinition(
      id: 'contacts_delete',
      groupId: 'contacts',
      groupName: 'Contacts',
      name: 'local_delete_contact',
      displayName: 'Delete contact',
      permission: LocalToolPermission.contacts,
      isSupported: () => isMobile,
      description: 'Local-only tool. Deletes a contact from the device.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
        },
        'required': ['id'],
      },
    ),
    LocalToolDefinition(
      id: 'sms',
      groupId: 'message',
      groupName: 'Message',
      name: 'local_compose_sms',
      displayName: 'Compose SMS',
      isSupported: () => isMobile,
      description:
          'Local-only tool. Creates an SMS compose link. The user must manually open the SMS app and tap send.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'phone_number': {'type': 'string'},
          'body': {'type': 'string'},
        },
        'required': ['phone_number', 'body'],
      },
    ),
    LocalToolDefinition(
      id: 'phone_call',
      groupId: 'call',
      groupName: 'Call',
      name: 'local_call_phone_number',
      displayName: 'Call phone number',
      isSupported: () => isMobile,
      description:
          'Local-only tool. Creates a tel: link. The user must manually tap it to open the dialer.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'phone_number': {'type': 'string'},
        },
        'required': ['phone_number'],
      },
    ),
    LocalToolDefinition(
      id: 'email',
      groupId: 'email',
      groupName: 'Email',
      name: 'local_compose_email',
      displayName: 'Compose email',
      isSupported: () => isMobile,
      description:
          'Local-only tool. Creates a mailto link. The user must manually open the mail app and send.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'to': {'type': 'string'},
          'subject': {'type': 'string'},
          'body': {'type': 'string'},
          'cc': {'type': 'string'},
          'bcc': {'type': 'string'},
        },
        'required': ['to'],
      },
    ),
    LocalToolDefinition(
      id: 'device_info',
      groupId: 'device_info',
      groupName: 'Device Info',
      name: 'local_get_device_info',
      displayName: 'Get device info',
      isSupported: () => !kIsWeb,
      description:
          'Local-only tool. Gets basic device, app, locale, timezone, and runtime information from this device.',
      inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    ),
    LocalToolDefinition(
      id: 'open_url',
      groupId: 'open_url',
      groupName: 'Open URL',
      name: 'local_open_url',
      displayName: 'Show URL open button',
      isSupported: () => true,
      description:
          'Local-only tool. Shows the full URL and a button the user must click to open it. Does not open URLs automatically.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string'},
          'label': {
            'type': 'string',
            'description': 'Optional short button label.',
          },
        },
        'required': ['url'],
      },
    ),
    LocalToolDefinition(
      id: 'alarm',
      groupId: 'alarm',
      groupName: 'Alarm',
      name: 'local_create_alarm',
      displayName: 'Create alarm',
      isSupported: () => !kIsWeb && Platform.isAndroid,
      description:
          'Local-only Android tool. Opens the device alarm app with an alarm time filled in; the user confirms in the alarm app.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'hour': {
            'type': 'integer',
            'description': '24-hour clock hour, 0-23.',
          },
          'minute': {'type': 'integer', 'description': 'Minute, 0-59.'},
          'label': {'type': 'string'},
        },
        'required': ['hour', 'minute'],
      },
    ),
    LocalToolDefinition(
      id: 'calendar_search',
      groupId: 'calendar',
      groupName: 'Calendar',
      name: 'local_search_calendar_events',
      displayName: 'Search calendar',
      permission: LocalToolPermission.calendar,
      isSupported: () => isMobile,
      description:
          'Local-only tool. Searches device calendar events in a date range.',
      inputSchema: _calendarSearchSchema,
    ),
    LocalToolDefinition(
      id: 'calendar_create',
      groupId: 'calendar',
      groupName: 'Calendar',
      name: 'local_create_calendar_event',
      displayName: 'Create calendar event',
      permission: LocalToolPermission.calendar,
      isSupported: () => isMobile,
      description: 'Local-only tool. Creates a device calendar event.',
      inputSchema: _calendarEventSchema(),
    ),
    LocalToolDefinition(
      id: 'calendar_update',
      groupId: 'calendar',
      groupName: 'Calendar',
      name: 'local_update_calendar_event',
      displayName: 'Update calendar event',
      permission: LocalToolPermission.calendar,
      isSupported: () => isMobile,
      description: 'Local-only tool. Updates a device calendar event.',
      inputSchema: _calendarEventSchema(requireEventId: true),
    ),
    LocalToolDefinition(
      id: 'calendar_delete',
      groupId: 'calendar',
      groupName: 'Calendar',
      name: 'local_delete_calendar_event',
      displayName: 'Delete calendar event',
      permission: LocalToolPermission.calendar,
      isSupported: () => isMobile,
      description: 'Local-only tool. Deletes a device calendar event.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'calendar_id': {'type': 'string'},
          'event_id': {'type': 'string'},
        },
        'required': ['calendar_id', 'event_id'],
      },
    ),
    LocalToolDefinition(
      id: 'reminders_search',
      groupId: 'reminders',
      groupName: 'Reminders',
      name: 'local_search_reminders',
      displayName: 'Search reminders',
      permission: LocalToolPermission.reminders,
      isSupported: () => isIos,
      description: 'Local-only iOS tool. Searches Apple Reminders.',
      inputSchema: _reminderSearchSchema,
    ),
    LocalToolDefinition(
      id: 'reminders_create',
      groupId: 'reminders',
      groupName: 'Reminders',
      name: 'local_create_reminder',
      displayName: 'Create reminder',
      permission: LocalToolPermission.reminders,
      isSupported: () => isIos,
      description: 'Local-only iOS tool. Creates an Apple Reminder.',
      inputSchema: _reminderSchema(),
    ),
    LocalToolDefinition(
      id: 'reminders_update',
      groupId: 'reminders',
      groupName: 'Reminders',
      name: 'local_update_reminder',
      displayName: 'Update reminder',
      permission: LocalToolPermission.reminders,
      isSupported: () => isIos,
      description: 'Local-only iOS tool. Updates an Apple Reminder.',
      inputSchema: _reminderSchema(requireId: true),
    ),
    LocalToolDefinition(
      id: 'reminders_delete',
      groupId: 'reminders',
      groupName: 'Reminders',
      name: 'local_delete_reminder',
      displayName: 'Delete reminder',
      permission: LocalToolPermission.reminders,
      isSupported: () => isIos,
      description: 'Local-only iOS tool. Deletes an Apple Reminder.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
        },
        'required': ['id'],
      },
    ),
  ];

  Future<String> _getTime(Map<String, dynamic> args) async {
    await _ensureTimeZonesInitialized();
    final requestedTimezone = args['timezone'] as String?;
    final timezone = requestedTimezone == null || requestedTimezone.isEmpty
        ? (await FlutterTimezone.getLocalTimezone()).identifier
        : requestedTimezone;
    final location = tz.getLocation(timezone);
    final now = tz.TZDateTime.now(location);
    return jsonEncode({
      'timezone': timezone,
      'iso8601': now.toIso8601String(),
      'formatted': DateFormat.yMMMMEEEEd().add_jms().format(now),
      'utcOffsetMinutes': now.timeZoneOffset.inMinutes,
      'timeZoneName': now.timeZoneName,
    });
  }

  static Future<void> _ensureTimeZonesInitialized() async {
    if (_timeZonesInitialized) return;
    tz_data.initializeTimeZones();
    try {
      final localTimezone =
          (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(localTimezone));
    } catch (_) {
      // Keep timezone.local at its package default if native timezone lookup fails.
    }
    _timeZonesInitialized = true;
  }

  Future<String> _getLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Error: Location services are disabled on this device.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return 'Error: Location permission was denied.';
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return jsonEncode({
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracyMeters': position.accuracy,
      'altitudeMeters': position.altitude,
      'speedMetersPerSecond': position.speed,
      'headingDegrees': position.heading,
      'timestamp': position.timestamp.toIso8601String(),
    });
  }

  Future<String> _searchContacts(Map<String, dynamic> args) async {
    final query = (args['query'] as String).toLowerCase();
    final limit = (args['limit'] as num?)?.toInt() ?? 10;
    final contacts = await FlutterContacts.getAll(
      properties: {
        ContactProperty.name,
        ContactProperty.phone,
        ContactProperty.email,
      },
      limit: 500,
    );
    final matches = contacts
        .where((contact) {
          final fields = [
            contact.displayName ?? '',
            ...contact.phones.map((p) => p.number),
            ...contact.emails.map((e) => e.address),
          ].map((value) => value.toLowerCase());
          return fields.any((value) => value.contains(query));
        })
        .take(limit)
        .map(_contactSummary)
        .toList();
    return jsonEncode({'contacts': matches});
  }

  Future<String> _getContact(Map<String, dynamic> args) async {
    final contact = await FlutterContacts.get(
      args['id'] as String,
      properties: {
        ContactProperty.name,
        ContactProperty.phone,
        ContactProperty.email,
        ContactProperty.organization,
        ContactProperty.address,
        ContactProperty.website,
      },
    );
    if (contact == null) return 'Error: Contact not found.';
    return jsonEncode(_contactDetails(contact));
  }

  Future<String> _createContact(Map<String, dynamic> args) async {
    final id = await FlutterContacts.create(_contactFromArgs(args));
    return jsonEncode({'created': true, 'id': id});
  }

  Future<String> _updateContact(Map<String, dynamic> args) async {
    final id = args['id'] as String;
    final existing = await FlutterContacts.get(
      id,
      properties: {
        ContactProperty.name,
        ContactProperty.phone,
        ContactProperty.email,
      },
    );
    if (existing == null) return 'Error: Contact not found.';
    await FlutterContacts.update(_contactFromArgs(args, existing: existing));
    return jsonEncode({'updated': true, 'id': id});
  }

  Future<String> _deleteContact(Map<String, dynamic> args) async {
    final id = args['id'] as String;
    await FlutterContacts.delete(id);
    return jsonEncode({'deleted': true, 'id': id});
  }

  String _composeSms(Map<String, dynamic> args) {
    final phoneNumber = args['phone_number'] as String;
    final body = args['body'] as String? ?? '';
    final uri = _smsUri(phoneNumber: phoneNumber, body: body);
    return jsonEncode({
      'type': 'local_action',
      'action': 'sms',
      'title': 'SMS draft',
      'label': 'Open SMS app',
      'url': uri.toString(),
      'displayUrl': uri.toString(),
      'phoneNumber': phoneNumber,
      'body': body,
      'requiresUserConfirmation': true,
    });
  }

  Uri _smsUri({required String phoneNumber, required String body}) {
    final encodedBody = Uri.encodeQueryComponent(body).replaceAll('+', '%20');
    return Uri.parse(
      'sms:${Uri.encodeComponent(phoneNumber)}${encodedBody.isNotEmpty ? '?body=$encodedBody' : ''}',
    );
  }

  String _callPhoneNumber(Map<String, dynamic> args) {
    final phoneNumber = args['phone_number'] as String;
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    return jsonEncode({
      'type': 'local_action',
      'action': 'call',
      'title': 'Phone call',
      'label': 'Open dialer',
      'url': uri.toString(),
      'displayUrl': uri.toString(),
      'phoneNumber': phoneNumber,
      'requiresUserConfirmation': true,
    });
  }

  String _composeEmail(Map<String, dynamic> args) {
    final queryParameters = <String, String>{};
    for (final key in ['subject', 'body', 'cc', 'bcc']) {
      final value = args[key] as String?;
      if (value != null && value.isNotEmpty) queryParameters[key] = value;
    }
    final uri = _mailtoUri(
      to: args['to'] as String,
      queryParameters: queryParameters,
    );
    return jsonEncode({
      'type': 'local_action',
      'action': 'email',
      'title': 'Email draft',
      'label': 'Open email app',
      'url': uri.toString(),
      'displayUrl': uri.toString(),
      'to': args['to'] as String,
      if (args['subject'] != null) 'subject': args['subject'] as String,
      if (args['body'] != null) 'body': args['body'] as String,
      if (args['cc'] != null) 'cc': args['cc'] as String,
      if (args['bcc'] != null) 'bcc': args['bcc'] as String,
      'requiresUserConfirmation': true,
    });
  }

  Uri _mailtoUri({
    required String to,
    required Map<String, String> queryParameters,
  }) {
    final encodedQuery = queryParameters.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value).replaceAll('+', '%20')}',
        )
        .join('&');
    return Uri.parse(
      'mailto:${Uri.encodeComponent(to)}${encodedQuery.isNotEmpty ? '?$encodedQuery' : ''}',
    );
  }

  Future<String> _getDeviceInfo() async {
    final localTimezone = !kIsWeb
        ? (await FlutterTimezone.getLocalTimezone()).identifier
        : 'unknown';
    return jsonEncode({
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'localTimezone': localTimezone,
      'numberOfProcessors': Platform.numberOfProcessors,
      'pathSeparator': Platform.pathSeparator,
      'executable': Platform.executable,
      'dartVersion': Platform.version,
      'isAndroid': Platform.isAndroid,
      'isIOS': Platform.isIOS,
      'isMacOS': Platform.isMacOS,
      'isWindows': Platform.isWindows,
      'isLinux': Platform.isLinux,
    });
  }

  String _openUrl(Map<String, dynamic> args) {
    final rawUrl = args['url'] as String;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme) {
      return 'Error: Invalid URL. The URL must include a scheme such as https://';
    }
    return jsonEncode({
      'type': 'local_action',
      'action': 'open_url',
      'title': 'Open URL',
      'url': uri.toString(),
      'displayUrl': uri.toString(),
      'label': args['label'] as String? ?? 'Open URL',
      'requiresUserConfirmation': true,
    });
  }

  Future<String> _createAlarm(Map<String, dynamic> args) async {
    if (!Platform.isAndroid) {
      return 'Error: Alarm creation is currently only supported on Android.';
    }
    final hour = (args['hour'] as num).toInt();
    final minute = (args['minute'] as num).toInt();
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return 'Error: Alarm time must use hour 0-23 and minute 0-59.';
    }
    final opened = await _alarmChannel.invokeMethod<bool>('createAlarm', {
      'hour': hour,
      'minute': minute,
      'label': args['label'] as String?,
    });
    return jsonEncode({
      'alarmAppOpened': opened == true,
      'hour': hour,
      'minute': minute,
      'label': args['label'] as String?,
      'requiresUserConfirmation': true,
    });
  }

  Future<String> _searchCalendarEvents(Map<String, dynamic> args) async {
    final calendars = await _writableOrReadableCalendars();
    final start = DateTime.parse(args['start'] as String);
    final end = DateTime.parse(args['end'] as String);
    final query = (args['query'] as String?)?.toLowerCase();
    final events = <Map<String, dynamic>>[];
    for (final calendar in calendars) {
      final calendarId = calendar.id;
      if (calendarId == null) continue;
      final result = await _calendarPlugin.retrieveEvents(
        calendarId,
        device_calendar.RetrieveEventsParams(startDate: start, endDate: end),
      );
      if (!result.isSuccess || result.data == null) continue;
      for (final event in result.data!) {
        if (query != null &&
            query.isNotEmpty &&
            !(event.title ?? '').toLowerCase().contains(query) &&
            !(event.description ?? '').toLowerCase().contains(query)) {
          continue;
        }
        events.add(_calendarEventToJson(calendar, event));
      }
    }
    return jsonEncode({'events': events});
  }

  Future<String> _createCalendarEvent(Map<String, dynamic> args) async {
    final calendar = await _selectCalendar(args['calendar_id'] as String?);
    if (calendar?.id == null) return 'Error: No writable calendar found.';
    final event = await _eventFromArgs(calendar!.id!, args);
    final result = await _calendarPlugin.createOrUpdateEvent(event);
    if (result?.isSuccess != true) {
      return 'Error: Failed to create calendar event: ${result?.errors.map((e) => e.errorMessage).join(', ')}';
    }
    return jsonEncode({
      'created': true,
      'calendarId': calendar.id,
      'eventId': result?.data,
    });
  }

  Future<String> _updateCalendarEvent(Map<String, dynamic> args) async {
    final calendarId = args['calendar_id'] as String;
    final event = await _eventFromArgs(
      calendarId,
      args,
      eventId: args['event_id'] as String,
    );
    final result = await _calendarPlugin.createOrUpdateEvent(event);
    if (result?.isSuccess != true) {
      return 'Error: Failed to update calendar event: ${result?.errors.map((e) => e.errorMessage).join(', ')}';
    }
    return jsonEncode({
      'updated': true,
      'calendarId': calendarId,
      'eventId': args['event_id'],
    });
  }

  Future<String> _deleteCalendarEvent(Map<String, dynamic> args) async {
    final result = await _calendarPlugin.deleteEvent(
      args['calendar_id'] as String,
      args['event_id'] as String,
    );
    if (!result.isSuccess || result.data != true) {
      return 'Error: Failed to delete calendar event: ${result.errors.map((e) => e.errorMessage).join(', ')}';
    }
    return jsonEncode({'deleted': true, 'eventId': args['event_id']});
  }

  Future<String> _invokeReminderTool(
    String action,
    Map<String, dynamic> args,
  ) async {
    if (!isIos) return 'Error: Reminders are only supported on iOS.';
    final result = await _remindersChannel.invokeMethod<dynamic>(action, args);
    return jsonEncode(result);
  }

  Future<List<device_calendar.Calendar>> _writableOrReadableCalendars() async {
    final permissions = await _calendarPlugin.requestPermissions();
    if (!permissions.isSuccess || permissions.data != true) {
      throw Exception('Calendar permission denied.');
    }
    final calendars = await _calendarPlugin.retrieveCalendars();
    if (!calendars.isSuccess || calendars.data == null) return [];
    return calendars.data!.toList();
  }

  Future<device_calendar.Calendar?> _selectCalendar(String? calendarId) async {
    final calendars = await _writableOrReadableCalendars();
    if (calendarId != null && calendarId.isNotEmpty) {
      return calendars.cast<device_calendar.Calendar?>().firstWhere(
        (calendar) => calendar!.id == calendarId,
        orElse: () => null,
      );
    }
    return calendars.cast<device_calendar.Calendar?>().firstWhere(
      (calendar) => calendar!.isReadOnly != true,
      orElse: () => null,
    );
  }

  Future<device_calendar.Event> _eventFromArgs(
    String calendarId,
    Map<String, dynamic> args, {
    String? eventId,
  }) async {
    await _ensureTimeZonesInitialized();
    final start = DateTime.parse(args['start'] as String);
    final end = DateTime.parse(args['end'] as String);
    return device_calendar.Event(
      calendarId,
      eventId: eventId,
      title: args['title'] as String?,
      description: args['description'] as String?,
      start: tz.TZDateTime.from(start, tz.local),
      end: tz.TZDateTime.from(end, tz.local),
      allDay: args['all_day'] as bool? ?? false,
    )..location = args['location'] as String?;
  }

  Map<String, dynamic> _calendarEventToJson(
    device_calendar.Calendar calendar,
    device_calendar.Event event,
  ) {
    return {
      'calendarId': calendar.id,
      'calendarName': calendar.name,
      'eventId': event.eventId,
      'title': event.title,
      'description': event.description,
      'start': event.start?.toIso8601String(),
      'end': event.end?.toIso8601String(),
      'allDay': event.allDay,
      'location': event.location,
    };
  }

  static Contact _contactFromArgs(
    Map<String, dynamic> args, {
    Contact? existing,
  }) {
    return (existing ?? const Contact()).copyWith(
      name: args['display_name'] != null
          ? Name(first: args['display_name'] as String)
          : existing?.name,
      phones: args['phones'] is List
          ? (args['phones'] as List)
                .map((phone) => Phone(number: phone.toString()))
                .toList()
          : existing?.phones,
      emails: args['emails'] is List
          ? (args['emails'] as List)
                .map((email) => Email(address: email.toString()))
                .toList()
          : existing?.emails,
    );
  }

  static Map<String, dynamic> _contactSummary(Contact contact) {
    return {
      'id': contact.id,
      'displayName': contact.displayName,
      'phones': contact.phones.map((phone) => phone.number).toList(),
      'emails': contact.emails.map((email) => email.address).toList(),
    };
  }

  static Map<String, dynamic> _contactDetails(Contact contact) {
    return {
      ..._contactSummary(contact),
      'organizations': contact.organizations
          .map((org) => org.toJson())
          .toList(),
      'addresses': contact.addresses
          .map((address) => address.toJson())
          .toList(),
      'websites': contact.websites.map((website) => website.toJson()).toList(),
    };
  }

  static Map<String, dynamic> _contactMutationSchema({
    bool requireId = false,
    bool requiredName = false,
  }) {
    return {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'display_name': {'type': 'string'},
        'phones': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'emails': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
      'required': [if (requireId) 'id', if (requiredName) 'display_name'],
    };
  }

  static const Map<String, dynamic> _calendarSearchSchema = {
    'type': 'object',
    'properties': {
      'start': {'type': 'string', 'description': 'ISO-8601 start datetime'},
      'end': {'type': 'string', 'description': 'ISO-8601 end datetime'},
      'query': {'type': 'string'},
    },
    'required': ['start', 'end'],
  };

  static Map<String, dynamic> _calendarEventSchema({
    bool requireEventId = false,
  }) {
    return {
      'type': 'object',
      'properties': {
        'calendar_id': {'type': 'string'},
        'event_id': {'type': 'string'},
        'title': {'type': 'string'},
        'description': {'type': 'string'},
        'start': {'type': 'string', 'description': 'ISO-8601 start datetime'},
        'end': {'type': 'string', 'description': 'ISO-8601 end datetime'},
        'location': {'type': 'string'},
        'all_day': {'type': 'boolean'},
      },
      'required': [
        if (requireEventId) ...['calendar_id', 'event_id'],
        'title',
        'start',
        'end',
      ],
    };
  }

  static const Map<String, dynamic> _reminderSearchSchema = {
    'type': 'object',
    'properties': {
      'query': {'type': 'string'},
      'include_completed': {'type': 'boolean', 'default': false},
    },
  };

  static Map<String, dynamic> _reminderSchema({bool requireId = false}) {
    return {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'title': {'type': 'string'},
        'notes': {'type': 'string'},
        'due_date': {
          'type': 'string',
          'description': 'Optional ISO-8601 due date',
        },
        'completed': {'type': 'boolean'},
      },
      'required': [if (requireId) 'id', 'title'],
    };
  }
}
