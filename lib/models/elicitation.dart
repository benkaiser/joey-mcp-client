/// Elicitation action types
enum ElicitationAction {
  accept,
  decline,
  cancel;

  String toJson() => name;

  static ElicitationAction fromString(String value) {
    return ElicitationAction.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ElicitationAction.cancel,
    );
  }
}

/// Elicitation mode
enum ElicitationMode {
  form,
  url;

  String toJson() => name;

  static ElicitationMode fromString(String value) {
    return ElicitationMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ElicitationMode.form,
    );
  }
}

/// Represents an elicitation request from an MCP server
class ElicitationRequest {
  final String id; // JSON-RPC request ID
  final ElicitationMode mode;
  final String message;
  final String? elicitationId; // For URL mode
  final String? url; // For URL mode
  final Map<String, dynamic>? requestedSchema; // For form mode

  ElicitationRequest({
    required this.id,
    required this.mode,
    required this.message,
    this.elicitationId,
    this.url,
    this.requestedSchema,
  });

  factory ElicitationRequest.fromJson(Map<String, dynamic> json) {
    final params = json['params'] as Map<String, dynamic>;
    final modeStr = params['mode'] as String? ?? 'form';
    final mode = ElicitationMode.fromString(modeStr);

    return ElicitationRequest(
      id: json['id'].toString(),
      mode: mode,
      message: params['message'] as String,
      elicitationId: params['elicitationId'] as String?,
      url: params['url'] as String?,
      requestedSchema: params['requestedSchema'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toResponseJson({
    required ElicitationAction action,
    Map<String, dynamic>? content,
  }) {
    final result = <String, dynamic>{
      'action': action.toJson(),
    };

    if (content != null && content.isNotEmpty) {
      result['content'] = content;
    }

    return {
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    };
  }
}

/// Form field types for rendering
enum FormFieldType {
  text,
  number,
  integer,
  boolean,
  singleSelect,
  multiSelect;

  static FormFieldType fromSchema(Map<String, dynamic> schema) {
    final type = schema['type'] as String?;

    if (type == 'boolean') {
      return FormFieldType.boolean;
    } else if (type == 'number') {
      return FormFieldType.number;
    } else if (type == 'integer') {
      return FormFieldType.integer;
    } else if (type == 'array') {
      return FormFieldType.multiSelect;
    } else if (schema.containsKey('enum') ||
        schema.containsKey('oneOf')) {
      return FormFieldType.singleSelect;
    } else {
      return FormFieldType.text;
    }
  }
}

/// Form field definition parsed from JSON schema
class ElicitationFormField {
  final String name;
  final FormFieldType type;
  final String? title;
  final String? description;
  final bool required;
  final dynamic defaultValue;
  final Map<String, dynamic> schema;

  // For string fields
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  final String? format;

  // For number fields
  final num? minimum;
  final num? maximum;

  // For enum fields
  final List<String>? enumValues;
  final Map<String, String>? enumTitles; // value -> title mapping

  // For array fields
  final int? minItems;
  final int? maxItems;

  ElicitationFormField({
    required this.name,
    required this.type,
    required this.schema,
    this.title,
    this.description,
    this.required = false,
    this.defaultValue,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.format,
    this.minimum,
    this.maximum,
    this.enumValues,
    this.enumTitles,
    this.minItems,
    this.maxItems,
  });

  factory ElicitationFormField.fromSchema(
    String fieldName,
    Map<String, dynamic> fieldSchema,
    bool isRequired,
  ) {
    final type = FormFieldType.fromSchema(fieldSchema);

    // Extract enum values and titles
    List<String>? enumValues;
    Map<String, String>? enumTitles;

    if (fieldSchema.containsKey('enum')) {
      enumValues =
          (fieldSchema['enum'] as List).map((e) => e.toString()).toList();
    } else if (fieldSchema.containsKey('oneOf')) {
      final oneOf = fieldSchema['oneOf'] as List;
      enumValues = [];
      enumTitles = {};
      for (final option in oneOf) {
        final optionMap = option as Map<String, dynamic>;
        final value = optionMap['const'].toString();
        enumValues.add(value);
        if (optionMap.containsKey('title')) {
          enumTitles[value] = optionMap['title'] as String;
        }
      }
    } else if (type == FormFieldType.multiSelect) {
      final items = fieldSchema['items'] as Map<String, dynamic>?;
      if (items != null) {
        if (items.containsKey('enum')) {
          enumValues =
              (items['enum'] as List).map((e) => e.toString()).toList();
        } else if (items.containsKey('anyOf')) {
          final anyOf = items['anyOf'] as List;
          enumValues = [];
          enumTitles = {};
          for (final option in anyOf) {
            final optionMap = option as Map<String, dynamic>;
            final value = optionMap['const'].toString();
            enumValues.add(value);
            if (optionMap.containsKey('title')) {
              enumTitles[value] = optionMap['title'] as String;
            }
          }
        }
      }
    }

    return ElicitationFormField(
      name: fieldName,
      type: type,
      schema: fieldSchema,
      title: fieldSchema['title'] as String?,
      description: fieldSchema['description'] as String?,
      required: isRequired,
      defaultValue: fieldSchema['default'],
      minLength: fieldSchema['minLength'] as int?,
      maxLength: fieldSchema['maxLength'] as int?,
      pattern: fieldSchema['pattern'] as String?,
      format: fieldSchema['format'] as String?,
      minimum: fieldSchema['minimum'] as num?,
      maximum: fieldSchema['maximum'] as num?,
      enumValues: enumValues,
      enumTitles: enumTitles,
      minItems: fieldSchema['minItems'] as int?,
      maxItems: fieldSchema['maxItems'] as int?,
    );
  }

  /// Validate a value against this field's schema
  String? validate(dynamic value) {
    if (required && (value == null || value == '')) {
      return 'This field is required';
    }

    if (value == null || value == '') {
      return null; // Optional field with no value is valid
    }

    switch (type) {
      case FormFieldType.text:
        if (value is! String) return 'Must be a string';
        if (minLength != null && value.length < minLength!) {
          return 'Minimum length is $minLength';
        }
        if (maxLength != null && value.length > maxLength!) {
          return 'Maximum length is $maxLength';
        }
        if (pattern != null) {
          final regex = RegExp(pattern!);
          if (!regex.hasMatch(value)) {
            return 'Does not match required pattern';
          }
        }
        if (format == 'email') {
          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
          if (!emailRegex.hasMatch(value)) {
            return 'Must be a valid email address';
          }
        }
        if (format == 'uri') {
          try {
            Uri.parse(value);
          } catch (e) {
            return 'Must be a valid URI';
          }
        }
        break;

      case FormFieldType.number:
      case FormFieldType.integer:
        final numValue = num.tryParse(value.toString());
        if (numValue == null) {
          return 'Must be a ${type == FormFieldType.integer ? 'integer' : 'number'}';
        }
        if (type == FormFieldType.integer && numValue != numValue.toInt()) {
          return 'Must be an integer';
        }
        if (minimum != null && numValue < minimum!) {
          return 'Minimum value is $minimum';
        }
        if (maximum != null && numValue > maximum!) {
          return 'Maximum value is $maximum';
        }
        break;

      case FormFieldType.boolean:
        if (value is! bool) return 'Must be true or false';
        break;

      case FormFieldType.singleSelect:
        if (enumValues != null && !enumValues!.contains(value.toString())) {
          return 'Must be one of: ${enumValues!.join(", ")}';
        }
        break;

      case FormFieldType.multiSelect:
        if (value is! List) return 'Must be a list';
        if (minItems != null && value.length < minItems!) {
          return 'Must select at least $minItems items';
        }
        if (maxItems != null && value.length > maxItems!) {
          return 'Must select at most $maxItems items';
        }
        if (enumValues != null) {
          for (final item in value) {
            if (!enumValues!.contains(item.toString())) {
              return 'Invalid option: $item';
            }
          }
        }
        break;
    }

    return null;
  }

  /// Get the display label for this field
  String get label => title ?? name;
}

/// Parsed form data from a form mode elicitation request
class ElicitationForm {
  final List<ElicitationFormField> fields;

  ElicitationForm({required this.fields});

  factory ElicitationForm.fromSchema(Map<String, dynamic> schema) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    final required = (schema['required'] as List?)?.cast<String>() ?? [];

    final fields = <ElicitationFormField>[];

    for (final entry in properties.entries) {
      final fieldName = entry.key;
      final fieldSchema = entry.value as Map<String, dynamic>;
      final isRequired = required.contains(fieldName);

      fields.add(ElicitationFormField.fromSchema(fieldName, fieldSchema, isRequired));
    }

    return ElicitationForm(fields: fields);
  }

  /// Validate all field values
  Map<String, String> validateAll(Map<String, dynamic> values) {
    final errors = <String, String>{};

    for (final field in fields) {
      final value = values[field.name];
      final error = field.validate(value);
      if (error != null) {
        errors[field.name] = error;
      }
    }

    return errors;
  }
}
