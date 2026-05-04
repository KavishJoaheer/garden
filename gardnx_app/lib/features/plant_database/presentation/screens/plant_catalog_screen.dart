import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gardnx_app/features/plant_database/domain/models/plant.dart';
import 'package:gardnx_app/features/plant_database/presentation/providers/plant_filter_provider.dart';
import 'package:gardnx_app/features/plant_database/presentation/providers/plant_provider.dart';
import 'package:gardnx_app/features/plant_database/presentation/screens/plant_detail_screen.dart';
import 'package:gardnx_app/features/plant_database/presentation/widgets/filter_chips.dart';
import 'package:gardnx_app/features/plant_database/presentation/widgets/plant_card.dart';
import 'package:gardnx_app/features/profile/presentation/providers/profile_provider.dart';

class PlantCatalogScreen extends ConsumerStatefulWidget {
  const PlantCatalogScreen({super.key});

  @override
  ConsumerState<PlantCatalogScreen> createState() => _PlantCatalogScreenState();
}

class _PlantCatalogScreenState extends ConsumerState<PlantCatalogScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    ref.read(plantFilterProvider.notifier).setSearchQuery(value);
    setState(() {}); // rebuild to toggle global search section
  }

  void _navigateToDetail(Plant plant) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlantDetailScreen(
          plantId: plant.id,
          // Pass the object directly for Perenual plants so we bypass Firestore
          preloadedPlant: plant.id.startsWith('perenual_') ? plant : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredAsync = ref.watch(filteredPlantsProvider);
    final activeCount = ref.watch(activeFilterCountProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final query = _searchController.text.trim();
    final showGlobal = query.length >= 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plant Catalog'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search plants...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  ),
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.filter_list),
                      onPressed: () => _showFilterSheet(context),
                    ),
                    if (activeCount > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: CircleAvatar(
                          radius: 8,
                          backgroundColor: colorScheme.primary,
                          child: Text(
                            '$activeCount',
                            style: TextStyle(
                              fontSize: 9,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              onChanged: _onSearchChanged,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          const PlantFilterChips(),
          // ── Preference filter banner ──────────────────────────────────
          _PreferencesFilterBanner(),
          const SizedBox(height: 4),
          Expanded(
            child: CustomScrollView(
              slivers: [
                // ── Section 1: Mauritius Collection ──────────────────────
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    icon: Icons.flag,
                    title: 'Mauritius Collection',
                    color: colorScheme.primary,
                  ),
                ),
                _LocalPlantsSliver(
                  filteredAsync: filteredAsync,
                  colorScheme: colorScheme,
                  theme: theme,
                  onNavigate: _navigateToDetail,
                  onClear: () {
                    _searchController.clear();
                    ref.read(plantFilterProvider.notifier).reset();
                  },
                ),

                // ── Section 2: Global Database (Perenual) ──────────────
                if (showGlobal) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      icon: Icons.public,
                      title: 'Global Database',
                      subtitle: 'Powered by Perenual',
                      color: Colors.teal,
                    ),
                  ),
                  _GlobalSearchSliver(
                    query: query,
                    onNavigate: _navigateToDetail,
                  ),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const PlantFilterChips(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Preference filter banner ─────────────────────────────────────────────────

class _PreferencesFilterBanner extends ConsumerWidget {
  const _PreferencesFilterBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFiltered = ref.watch(isFilteredByPreferencesProvider);
    if (!isFiltered) return const SizedBox.shrink();

    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    final types = profile?.preferences.plantTypes ?? [];
    final label = types.map((t) => t[0].toUpperCase() + t.substring(1)).join(', ');
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined, size: 16, color: Colors.teal),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Filtered by your preferences: $label',
              style: const TextStyle(fontSize: 12, color: Colors.teal),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(plantFilterProvider.notifier).showAll(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Show all',
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 6),
            Text(
              subtitle!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Local (Mauritius) plants sliver ──────────────────────────────────────────

class _LocalPlantsSliver extends StatelessWidget {
  final AsyncValue<List<Plant>> filteredAsync;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final void Function(Plant) onNavigate;
  final VoidCallback onClear;

  const _LocalPlantsSliver({
    required this.filteredAsync,
    required this.colorScheme,
    required this.theme,
    required this.onNavigate,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return filteredAsync.when(
      data: (plants) {
        if (plants.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 48,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No local plants found',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: onClear, child: const Text('Clear filters')),
                ],
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => PlantCard(
                plant: plants[index],
                onTap: () => onNavigate(plants[index]),
              ),
              childCount: plants.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(child: _ShimmerGrid()),
      error: (e, _) => SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load plants', style: theme.textTheme.bodyLarge),
          ),
        ),
      ),
    );
  }
}

// ── Global (Perenual) search sliver ──────────────────────────────────────────

class _GlobalSearchSliver extends ConsumerWidget {
  final String query;
  final void Function(Plant) onNavigate;

  const _GlobalSearchSliver({
    required this.query,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final globalAsync = ref.watch(globalPlantSearchProvider(query));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return globalAsync.when(
      data: (plants) {
        if (plants.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: Text(
                'No global results for "$query"',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => PlantCard(
                plant: plants[index],
                onTap: () => onNavigate(plants[index]),
              ),
              childCount: plants.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, __) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Text(
            'Global search unavailable — check your connection.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shimmer placeholder ───────────────────────────────────────────────────────

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 80,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
