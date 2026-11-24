class BuildSeed {
  const BuildSeed({required this.weaponId, required this.fixedIds, required this.targets, required this.jewelCounts});
  final String weaponId;
  final List<String> fixedIds;
  final Map<String, int> targets;
  final Map<String, int> jewelCounts;
}

BuildSeed seedFor(String gameId) {
  if (gameId == 'wilds') {
    return const BuildSeed(
      weaponId: 'fixture-weapon-w',
      fixedIds: ['fixture-weapon-w', 'fixture-head-h'],
      targets: {'fixture-skill-y': 1},
      jewelCounts: {},
    );
  }
  return const BuildSeed(
    weaponId: 'fixture-iron-sword',
    fixedIds: ['fixture-fixed-mail', 'fixture-iron-sword'],
    targets: {'fixture-skill-s': 3},
    jewelCounts: {'fixture-attack-jewel': 2},
  );
}
