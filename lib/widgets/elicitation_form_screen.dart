import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/elicitation.dart';

/// Full-screen form for form mode elicitation requests
class ElicitationFormScreen extends StatefulWidget {
  final ElicitationRequest request;
  final ElicitationForm form;

  const ElicitationFormScreen({
    super.key,
    required this.request,
    required this.form,
  });

  @override
  State<ElicitationFormScreen> createState() => _ElicitationFormScreenState();
}

class _ElicitationFormScreenState extends State<ElicitationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    // Initialize with default values
    for (final field in widget.form.fields) {
      if (field.defaultValue != null) {
        _values[field.name] = field.defaultValue;
      } else if (field.type == FormFieldType.multiSelect) {
        _values[field.name] = <String>[];
      }
    }
  }

  void _submit() {
    setState(() => _errors.clear());

    // Validate all fields
    final errors = widget.form.validateAll(_values);
    if (errors.isNotEmpty) {
      setState(() => _errors.addAll(errors));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix the errors before submitting'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Return accept with content
    Navigator.pop(context, {'action': ElicitationAction.accept, 'content': _values});
  }

  void _decline() {
    Navigator.pop(context, {'action': ElicitationAction.decline});
  }

  Widget _buildField(ElicitationFormField field) {
    switch (field.type) {
      case FormFieldType.text:
        return _buildTextField(field);
      case FormFieldType.number:
      case FormFieldType.integer:
        return _buildNumberField(field);
      case FormFieldType.boolean:
        return _buildBooleanField(field);
      case FormFieldType.singleSelect:
        return _buildSingleSelectField(field);
      case FormFieldType.multiSelect:
        return _buildMultiSelectField(field);
    }
  }

  Widget _buildTextField(ElicitationFormField field) {
    final controller = TextEditingController(
      text: _values[field.name]?.toString() ?? '',
    );

    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.description,
        border: const OutlineInputBorder(),
        errorText: _errors[field.name],
      ),
      maxLines: field.format == null ? 1 : null,
      keyboardType: field.format == 'email'
          ? TextInputType.emailAddress
          : field.format == 'uri'
              ? TextInputType.url
              : TextInputType.text,
      onChanged: (value) {
        setState(() {
          _values[field.name] = value;
          _errors.remove(field.name);
        });
      },
    );
  }

  Widget _buildNumberField(ElicitationFormField field) {
    final controller = TextEditingController(
      text: _values[field.name]?.toString() ?? '',
    );

    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.description,
        border: const OutlineInputBorder(),
        errorText: _errors[field.name],
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: field.type == FormFieldType.integer
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      onChanged: (value) {
        setState(() {
          if (value.isEmpty) {
            _values[field.name] = null;
          } else if (field.type == FormFieldType.integer) {
            _values[field.name] = int.tryParse(value);
          } else {
            _values[field.name] = num.tryParse(value);
          }
          _errors.remove(field.name);
        });
      },
    );
  }

  Widget _buildBooleanField(ElicitationFormField field) {
    final value = _values[field.name] as bool? ?? false;

    return FormField<bool>(
      initialValue: value,
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: Text(field.label),
              subtitle: field.description != null
                  ? Text(field.description!)
                  : null,
              value: value,
              onChanged: (newValue) {
                setState(() {
                  _values[field.name] = newValue;
                  _errors.remove(field.name);
                });
              },
            ),
            if (_errors[field.name] != null)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Text(
                  _errors[field.name]!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSingleSelectField(ElicitationFormField field) {
    final value = _values[field.name]?.toString();

    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.description,
        border: const OutlineInputBorder(),
        errorText: _errors[field.name],
      ),
      items: field.enumValues?.map((enumValue) {
        final title = field.enumTitles?[enumValue] ?? enumValue;
        return DropdownMenuItem(
          value: enumValue,
          child: Text(title),
        );
      }).toList(),
      onChanged: (newValue) {
        setState(() {
          _values[field.name] = newValue;
          _errors.remove(field.name);
        });
      },
    );
  }

  Widget _buildMultiSelectField(ElicitationFormField field) {
    final selectedValues = _values[field.name] as List<String>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (field.description != null) ...[
          const SizedBox(height: 4),
          Text(
            field.description!,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        ...?field.enumValues?.map((enumValue) {
          final title = field.enumTitles?[enumValue] ?? enumValue;
          final isSelected = selectedValues.contains(enumValue);

          return CheckboxListTile(
            title: Text(title),
            value: isSelected,
            onChanged: (checked) {
              setState(() {
                final list = _values[field.name] as List<String>? ?? [];
                if (checked == true && !list.contains(enumValue)) {
                  list.add(enumValue);
                } else if (checked == false) {
                  list.remove(enumValue);
                }
                _values[field.name] = list;
                _errors.remove(field.name);
              });
            },
          );
        }).toList(),
        if (_errors[field.name] != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Text(
              _errors[field.name]!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fill Form'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.pop(context, {'action': ElicitationAction.cancel});
          },
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.request.message,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ...widget.form.fields.map((field) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildField(field),
              );
            }).toList(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _decline,
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Submit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
