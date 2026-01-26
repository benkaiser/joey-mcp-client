import 'package:flutter/material.dart';
import '../services/openrouter_service.dart';
import '../services/default_model_service.dart';

class ModelPickerScreen extends StatefulWidget {
  final String? defaultModel;

  const ModelPickerScreen({super.key, this.defaultModel});

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  final OpenRouterService _openRouterService = OpenRouterService();
  List<Map<String, dynamic>>? _models;
  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  String? _selectedDefaultModel;

  @override
  void initState() {
    super.initState();
    _selectedDefaultModel = widget.defaultModel;
    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final models = await _openRouterService.getModels();
      setState(() {
        _models = models;
        _isLoading = false;
      });
    } on OpenRouterAuthException {
      if (mounted) {
        // Navigate to auth screen - replace entire navigation stack
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/auth', (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredModels {
    if (_models == null) return [];
    if (_searchQuery.isEmpty) return _models!;

    return _models!.where((model) {
      final name = (model['name'] as String? ?? '').toLowerCase();
      final id = (model['id'] as String? ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || id.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Model'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_selectedDefaultModel != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Chip(
                avatar: const Icon(Icons.stars, size: 16),
                label: const Text('Default set'),
                labelStyle: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search models...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Model list
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Failed to load models',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadModels,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final filteredModels = _filteredModels;

    if (filteredModels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No models found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredModels.length,
      itemBuilder: (context, index) {
        final model = filteredModels[index];
        return _ModelListItem(
          model: model,
          isDefault: _selectedDefaultModel == model['id'],
          onTap: () {
            Navigator.pop(context, model['id'] as String);
          },
          onDefaultToggle: (bool value) async {
            if (value) {
              await DefaultModelService.setDefaultModel(model['id'] as String);
              setState(() {
                _selectedDefaultModel = model['id'] as String;
              });
            } else {
              // Unchecking - handled via settings screen
              setState(() {
                _selectedDefaultModel = null;
              });
            }
          },
        );
      },
    );
  }
}

class _ModelListItem extends StatelessWidget {
  final Map<String, dynamic> model;
  final VoidCallback onTap;
  final bool isDefault;
  final Function(bool) onDefaultToggle;

  const _ModelListItem({
    required this.model,
    required this.onTap,
    required this.isDefault,
    required this.onDefaultToggle,
  });

  @override
  Widget build(BuildContext context) {
    final name = model['name'] as String? ?? 'Unknown Model';
    final id = model['id'] as String? ?? '';
    final description = model['description'] as String? ?? '';
    final pricing = model['pricing'] as Map<String, dynamic>?;
    final contextLength = model['context_length'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Model name
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (isDefault)
                              const Padding(
                                padding: EdgeInsets.only(left: 8.0),
                                child: Icon(
                                  Icons.stars,
                                  color: Colors.amber,
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Model ID
                        Text(
                          id,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.grey[600],
                                fontFamily: 'monospace',
                              ),
                        ),
                      ],
                    ),
                  ),
                  // Default checkbox
                  Column(
                    children: [
                      Checkbox(
                        value: isDefault,
                        onChanged: (bool? value) {
                          if (value != null) {
                            onDefaultToggle(value);
                          }
                        },
                      ),
                      Text(
                        'Default',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),

              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 8),

              // Metadata row
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (contextLength > 0)
                    _InfoChip(
                      icon: Icons.storage,
                      label: '${_formatNumber(contextLength)} tokens',
                    ),
                  if (pricing != null && pricing['completion'] != null)
                    _InfoChip(
                      icon: Icons.attach_money,
                      label: _formatPricing(pricing['completion']),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}K';
    }
    return number.toString();
  }

  String _formatPricing(dynamic pricePerToken) {
    if (pricePerToken == null) return '\$0/M out';

    final price = double.tryParse(pricePerToken.toString()) ?? 0.0;
    final pricePerMillion = price * 1000000;

    if (pricePerMillion == 0) {
      return 'Free';
    } else if (pricePerMillion < 0.01) {
      return '${pricePerMillion.toStringAsFixed(4)}/M out';
    } else {
      return '${pricePerMillion.toStringAsFixed(2)}/M out';
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
