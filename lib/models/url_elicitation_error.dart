import 'elicitation.dart';

/// Exception thrown when a server requires URL mode elicitation before proceeding
class URLElicitationRequiredError implements Exception {
  final String message;
  final List<ElicitationRequest> elicitations;

  URLElicitationRequiredError({
    required this.message,
    required this.elicitations,
  });

  factory URLElicitationRequiredError.fromJson(Map<String, dynamic> errorData) {
    final data = errorData['data'] as Map<String, dynamic>?;
    final elicitationsList = data?['elicitations'] as List? ?? [];

    final elicitations = elicitationsList.map((e) {
      final elicitationMap = e as Map<String, dynamic>;
      // Convert to a format that ElicitationRequest.fromJson expects
      return ElicitationRequest.fromJson({
        'id': 'error-${DateTime.now().millisecondsSinceEpoch}',
        'params': elicitationMap,
      });
    }).toList();

    return URLElicitationRequiredError(
      message: errorData['message'] as String? ?? 'URL elicitation required',
      elicitations: elicitations,
    );
  }

  @override
  String toString() =>
      'URLElicitationRequiredError: $message (${elicitations.length} elicitations required)';
}
