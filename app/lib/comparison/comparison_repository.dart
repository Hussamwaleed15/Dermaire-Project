import 'comparison_domain.dart';

/// Context carries identity/generation, never token strings or public image URLs.
class ComparisonReadContext {
  const ComparisonReadContext(this.owner, this.generation);
  final String owner;
  final int generation;
}

class ComparisonUnsupported implements Exception {
  const ComparisonUnsupported();
}

/// Proposed domain boundary only. Future adapters must verify the wire contract,
/// authorization, source/relationship evidence, freshness and revisions BEFORE
/// creating domain snapshots. This interface supplies no HTTP endpoint/schema.
abstract interface class ComparisonRepository {
  Future<List<ComparisonPlan>> readPlans(ComparisonReadContext context);
  Future<ComparisonSnapshot?> readPlan(
    String id,
    ComparisonReadContext context,
  );
}

/// The actual default adapter. Missing contracts do not become fabricated empty
/// plans, schedules, AI replies or HTTP calls. No adapter is enabled in app state.
class UnsupportedComparisonRepository implements ComparisonRepository {
  const UnsupportedComparisonRepository();
  @override
  Future<List<ComparisonPlan>> readPlans(ComparisonReadContext context) async =>
      throw const ComparisonUnsupported();
  @override
  Future<ComparisonSnapshot?> readPlan(
    String id,
    ComparisonReadContext context,
  ) async => throw const ComparisonUnsupported();
}
