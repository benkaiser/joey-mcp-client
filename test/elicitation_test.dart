import 'package:flutter_test/flutter_test.dart';
import 'package:joey_mcp_client_flutter/models/elicitation.dart';
import 'package:joey_mcp_client_flutter/models/url_elicitation_error.dart';

void main() {
  group('ElicitationRequest', () {
    test('should parse form mode elicitation request', () {
      final json = {
        'id': '123',
        'params': {
          'mode': 'form',
          'message': 'Please provide your name',
          'requestedSchema': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
            },
            'required': ['name'],
          },
        },
      };

      final request = ElicitationRequest.fromJson(json);

      expect(request.id, equals('123'));
      expect(request.mode, equals(ElicitationMode.form));
      expect(request.message, equals('Please provide your name'));
      expect(request.requestedSchema, isNotNull);
      expect(request.url, isNull);
      expect(request.elicitationId, isNull);
    });

    test('should parse URL mode elicitation request', () {
      final json = {
        'id': '456',
        'params': {
          'mode': 'url',
          'message': 'Please authorize access',
          'url': 'https://example.com/auth',
          'elicitationId': 'elicit-123',
        },
      };

      final request = ElicitationRequest.fromJson(json);

      expect(request.id, equals('456'));
      expect(request.mode, equals(ElicitationMode.url));
      expect(request.message, equals('Please authorize access'));
      expect(request.url, equals('https://example.com/auth'));
      expect(request.elicitationId, equals('elicit-123'));
      expect(request.requestedSchema, isNull);
    });

    test('should default to form mode when mode is omitted', () {
      final json = {
        'id': '789',
        'params': {
          'message': 'Please provide info',
          'requestedSchema': {
            'type': 'object',
            'properties': {},
          },
        },
      };

      final request = ElicitationRequest.fromJson(json);

      expect(request.mode, equals(ElicitationMode.form));
    });

    test('should create accept response JSON with content', () {
      final request = ElicitationRequest(
        id: '123',
        mode: ElicitationMode.form,
        message: 'Test',
      );

      final response = request.toResponseJson(
        action: ElicitationAction.accept,
        content: {'name': 'John Doe'},
      );

      expect(response['jsonrpc'], equals('2.0'));
      expect(response['id'], equals('123'));
      expect(response['result']['action'], equals('accept'));
      expect(response['result']['content'], equals({'name': 'John Doe'}));
    });

    test('should create decline response JSON without content', () {
      final request = ElicitationRequest(
        id: '456',
        mode: ElicitationMode.url,
        message: 'Test',
      );

      final response = request.toResponseJson(
        action: ElicitationAction.decline,
      );

      expect(response['jsonrpc'], equals('2.0'));
      expect(response['id'], equals('456'));
      expect(response['result']['action'], equals('decline'));
      expect(response['result']['content'], isNull);
    });
  });

  group('ElicitationFormField', () {
    test('should validate required string field', () {
      final field = ElicitationFormField.fromSchema(
        'username',
        {
          'type': 'string',
          'title': 'Username',
        },
        true, // required
      );

      expect(field.validate(null), equals('This field is required'));
      expect(field.validate(''), equals('This field is required'));
      expect(field.validate('john'), isNull);
    });

    test('should validate string length constraints', () {
      final field = ElicitationFormField.fromSchema(
        'password',
        {
          'type': 'string',
          'minLength': 8,
          'maxLength': 20,
        },
        false,
      );

      expect(field.validate('short'), contains('Minimum length is 8'));
      expect(field.validate('a' * 21), contains('Maximum length is 20'));
      expect(field.validate('validpass'), isNull);
    });

    test('should validate email format', () {
      final field = ElicitationFormField.fromSchema(
        'email',
        {
          'type': 'string',
          'format': 'email',
        },
        false,
      );

      expect(field.validate('not-an-email'), contains('valid email'));
      expect(field.validate('test@example.com'), isNull);
    });

    test('should validate number constraints', () {
      final field = ElicitationFormField.fromSchema(
        'age',
        {
          'type': 'number',
          'minimum': 0,
          'maximum': 120,
        },
        false,
      );

      expect(field.validate(-1), contains('Minimum value is 0'));
      expect(field.validate(121), contains('Maximum value is 120'));
      expect(field.validate(25), isNull);
    });

    test('should validate integer type', () {
      final field = ElicitationFormField.fromSchema(
        'count',
        {'type': 'integer'},
        false,
      );

      expect(field.validate('3.14'), contains('integer'));
      expect(field.validate('5'), isNull);
    });

    test('should validate boolean field', () {
      final field = ElicitationFormField.fromSchema(
        'agree',
        {'type': 'boolean'},
        false,
      );

      expect(field.validate('yes'), contains('true or false'));
      expect(field.validate(true), isNull);
      expect(field.validate(false), isNull);
    });

    test('should validate single-select enum', () {
      final field = ElicitationFormField.fromSchema(
        'color',
        {
          'type': 'string',
          'enum': ['red', 'green', 'blue'],
        },
        false,
      );

      expect(field.validate('yellow'), contains('Must be one of'));
      expect(field.validate('red'), isNull);
    });

    test('should validate multi-select with minItems and maxItems', () {
      final field = ElicitationFormField.fromSchema(
        'colors',
        {
          'type': 'array',
          'minItems': 1,
          'maxItems': 2,
          'items': {
            'type': 'string',
            'enum': ['red', 'green', 'blue'],
          },
        },
        false,
      );

      expect(field.validate([]), contains('at least 1'));
      expect(field.validate(['red', 'green', 'blue']), contains('at most 2'));
      expect(field.validate(['red', 'green']), isNull);
    });

    test('should parse enum with titles', () {
      final field = ElicitationFormField.fromSchema(
        'priority',
        {
          'type': 'string',
          'oneOf': [
            {'const': 'high', 'title': 'High Priority'},
            {'const': 'low', 'title': 'Low Priority'},
          ],
        },
        false,
      );

      expect(field.enumValues, equals(['high', 'low']));
      expect(field.enumTitles?['high'], equals('High Priority'));
      expect(field.enumTitles?['low'], equals('Low Priority'));
    });

    test('should use default value', () {
      final field = ElicitationFormField.fromSchema(
        'country',
        {
          'type': 'string',
          'default': 'US',
        },
        false,
      );

      expect(field.defaultValue, equals('US'));
    });
  });

  group('ElicitationForm', () {
    test('should parse form schema with multiple fields', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'number'},
          'agree': {'type': 'boolean'},
        },
        'required': ['name', 'agree'],
      };

      final form = ElicitationForm.fromSchema(schema);

      expect(form.fields.length, equals(3));
      expect(form.fields[0].name, equals('name'));
      expect(form.fields[0].required, isTrue);
      expect(form.fields[1].name, equals('age'));
      expect(form.fields[1].required, isFalse);
      expect(form.fields[2].name, equals('agree'));
      expect(form.fields[2].required, isTrue);
    });

    test('should validate all fields', () {
      final schema = {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'number', 'minimum': 0},
        },
        'required': ['name'],
      };

      final form = ElicitationForm.fromSchema(schema);

      final errors = form.validateAll({
        'name': '', // Required but empty
        'age': -5, // Below minimum
      });

      expect(errors['name'], contains('required'));
      expect(errors['age'], contains('Minimum'));
    });

    test('should pass validation with valid values', () {
      final schema = {
        'type': 'object',
        'properties': {
          'email': {'type': 'string', 'format': 'email'},
          'age': {'type': 'integer', 'minimum': 18},
        },
        'required': ['email'],
      };

      final form = ElicitationForm.fromSchema(schema);

      final errors = form.validateAll({
        'email': 'test@example.com',
        'age': 25,
      });

      expect(errors, isEmpty);
    });
  });

  group('URLElicitationRequiredError', () {
    test('should parse error with elicitations', () {
      final errorData = {
        'code': -32042,
        'message': 'Authorization required',
        'data': {
          'elicitations': [
            {
              'mode': 'url',
              'url': 'https://example.com/auth',
              'message': 'Please authorize',
              'elicitationId': 'auth-123',
            },
          ],
        },
      };

      final error = URLElicitationRequiredError.fromJson(errorData);

      expect(error.message, equals('Authorization required'));
      expect(error.elicitations.length, equals(1));
      expect(error.elicitations[0].mode, equals(ElicitationMode.url));
      expect(error.elicitations[0].url, equals('https://example.com/auth'));
      expect(error.elicitations[0].elicitationId, equals('auth-123'));
    });

    test('should handle multiple elicitations', () {
      final errorData = {
        'code': -32042,
        'message': 'Multiple authorizations required',
        'data': {
          'elicitations': [
            {
              'mode': 'url',
              'url': 'https://service1.com/auth',
              'message': 'Authorize service 1',
              'elicitationId': 'auth-1',
            },
            {
              'mode': 'url',
              'url': 'https://service2.com/auth',
              'message': 'Authorize service 2',
              'elicitationId': 'auth-2',
            },
          ],
        },
      };

      final error = URLElicitationRequiredError.fromJson(errorData);

      expect(error.elicitations.length, equals(2));
      expect(error.elicitations[0].elicitationId, equals('auth-1'));
      expect(error.elicitations[1].elicitationId, equals('auth-2'));
    });

    test('should have informative toString', () {
      final error = URLElicitationRequiredError(
        message: 'Auth needed',
        elicitations: [
          ElicitationRequest(
            id: '1',
            mode: ElicitationMode.url,
            message: 'Test',
          ),
        ],
      );

      expect(
        error.toString(),
        contains('URLElicitationRequiredError'),
      );
      expect(error.toString(), contains('Auth needed'));
      expect(error.toString(), contains('1 elicitations required'));
    });
  });

  group('FormFieldType', () {
    test('should detect text type', () {
      expect(
        FormFieldType.fromSchema({'type': 'string'}),
        equals(FormFieldType.text),
      );
    });

    test('should detect number type', () {
      expect(
        FormFieldType.fromSchema({'type': 'number'}),
        equals(FormFieldType.number),
      );
    });

    test('should detect integer type', () {
      expect(
        FormFieldType.fromSchema({'type': 'integer'}),
        equals(FormFieldType.integer),
      );
    });

    test('should detect boolean type', () {
      expect(
        FormFieldType.fromSchema({'type': 'boolean'}),
        equals(FormFieldType.boolean),
      );
    });

    test('should detect single-select from enum', () {
      expect(
        FormFieldType.fromSchema({
          'type': 'string',
          'enum': ['a', 'b'],
        }),
        equals(FormFieldType.singleSelect),
      );
    });

    test('should detect single-select from oneOf', () {
      expect(
        FormFieldType.fromSchema({
          'type': 'string',
          'oneOf': [
            {'const': 'a'},
            {'const': 'b'},
          ],
        }),
        equals(FormFieldType.singleSelect),
      );
    });

    test('should detect multi-select from array', () {
      expect(
        FormFieldType.fromSchema({'type': 'array'}),
        equals(FormFieldType.multiSelect),
      );
    });
  });

  group('ElicitationAction', () {
    test('should convert to JSON', () {
      expect(ElicitationAction.accept.toJson(), equals('accept'));
      expect(ElicitationAction.decline.toJson(), equals('decline'));
      expect(ElicitationAction.cancel.toJson(), equals('cancel'));
    });

    test('should parse from string', () {
      expect(
        ElicitationAction.fromString('accept'),
        equals(ElicitationAction.accept),
      );
      expect(
        ElicitationAction.fromString('decline'),
        equals(ElicitationAction.decline),
      );
      expect(
        ElicitationAction.fromString('cancel'),
        equals(ElicitationAction.cancel),
      );
    });

    test('should default to cancel for unknown string', () {
      expect(
        ElicitationAction.fromString('unknown'),
        equals(ElicitationAction.cancel),
      );
    });
  });

  group('ElicitationMode', () {
    test('should convert to JSON', () {
      expect(ElicitationMode.form.toJson(), equals('form'));
      expect(ElicitationMode.url.toJson(), equals('url'));
    });

    test('should parse from string', () {
      expect(
        ElicitationMode.fromString('form'),
        equals(ElicitationMode.form),
      );
      expect(
        ElicitationMode.fromString('url'),
        equals(ElicitationMode.url),
      );
    });

    test('should default to form for unknown string', () {
      expect(
        ElicitationMode.fromString('unknown'),
        equals(ElicitationMode.form),
      );
    });
  });
}
