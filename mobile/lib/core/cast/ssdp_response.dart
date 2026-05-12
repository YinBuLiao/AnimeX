/// Parses an SSDP HTTP-style response (or M-SEARCH request).
///
/// The first line is the status line (e.g. "HTTP/1.1 200 OK"). All subsequent
/// non-empty lines are `Name: value` header pairs. Header names are normalized
/// to upper case to match how SSDP devices vary in capitalization.
Map<String, String> parseSsdpResponse(String raw) {
  final headers = <String, String>{};
  final lines = raw.split(RegExp(r'\r?\n'));
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final name = line.substring(0, colon).trim().toUpperCase();
    final value = line.substring(colon + 1).trim();
    if (name.isEmpty) continue;
    headers[name] = value;
  }
  return headers;
}
