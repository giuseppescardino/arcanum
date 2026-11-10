/// Groups form a tree: an item's group is a path whose levels are
/// separated by [groupSeparator], e.g. `Work/Clients`.
library;

const groupSeparator = '/';

/// Canonical form of a path: levels trimmed, empty ones dropped.
String normalizeGroup(String path) => path
    .split(groupSeparator)
    .map((level) => level.trim())
    .where((level) => level.isNotEmpty)
    .join(groupSeparator);

/// First level of [path]: the group shown in the filter bar.
String groupRoot(String path) {
  final i = path.indexOf(groupSeparator);
  return i < 0 ? path : path.substring(0, i);
}

/// Last level of [path]: the name shown in the list.
String groupLeaf(String path) =>
    path.substring(path.lastIndexOf(groupSeparator) + 1);

/// How many levels sit above [path]; 0 for a root group.
int groupDepth(String path) => groupSeparator.allMatches(path).length;

/// Whether [path] is [ancestor] itself or one of its subgroups.
bool groupContains(String ancestor, String path) =>
    path == ancestor || path.startsWith('$ancestor$groupSeparator');

/// Groups above [path], outermost first: `A/B/C` gives `A`, `A/B`.
List<String> groupAncestors(String path) {
  final levels = path.split(groupSeparator);
  return [
    for (var i = 1; i < levels.length; i++)
      levels.sublist(0, i).join(groupSeparator),
  ];
}

/// Every group in [paths] plus the parents they imply, in tree order:
/// each group is followed by its subgroups, siblings sorted
/// case-insensitively.
List<String> groupTree(Iterable<String> paths) {
  final all = <String>{};
  for (final path in paths) {
    if (path.isEmpty) continue;
    all
      ..addAll(groupAncestors(path))
      ..add(path);
  }
  return all.toList()..sort(_compareGroups);
}

int _compareGroups(String a, String b) {
  final x = a.toLowerCase().split(groupSeparator);
  final y = b.toLowerCase().split(groupSeparator);
  for (var i = 0; i < x.length && i < y.length; i++) {
    final c = x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}
