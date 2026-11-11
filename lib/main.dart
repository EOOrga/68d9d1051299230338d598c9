import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String appName = 'ASS DE GESTION DE LA BASE DE L';
const String companyName = 'ASS DE GESTION DE LA BASE DE LOISIRS';
const String supportEmail = 'contact@assgestionbase.app';
const bool kScreenshotMode = bool.fromEnvironment('SCREENSHOT_MODE');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.screenshotMode = kScreenshotMode});

  final bool screenshotMode;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final OperationsStore _store;
  late final Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _store = OperationsStore(screenshotMode: widget.screenshotMode);
    _loadFuture = _store.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            home: const LoadingView(),
          );
        }

        return StoreScope(
          notifier: _store,
          child: AssGestionApp(screenshotMode: widget.screenshotMode),
        );
      },
    );
  }
}

class AssGestionApp extends StatelessWidget {
  const AssGestionApp({super.key, required this.screenshotMode});

  final bool screenshotMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeShell(screenshotMode: screenshotMode),
    );
  }
}

ThemeData buildTheme() {
  const Color primary = Color(0xFF013A63);
  const Color secondary = Color(0xFF0EA5C6);
  const Color tertiary = Color(0xFF3E8F5E);
  const Color warning = Color(0xFFE9A23B);
  const Color surface = Color(0xFFF5F8FB);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: primary,
        secondary: secondary,
        tertiary: tertiary,
        error: const Color(0xFFB3261E),
        surface: surface,
        surfaceContainerHighest: const Color(0xFFE1EDF3),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: surface,
      foregroundColor: Color(0xFF082033),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Color(0xFFD7E5EC)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
    chipTheme: ChipThemeData(
      selectedColor: secondary.withValues(alpha: 0.16),
      checkmarkColor: primary,
      side: const BorderSide(color: Color(0xFFC8D9E2)),
    ),
    extensions: const <ThemeExtension<dynamic>>[
      StatusColors(
        planned: warning,
        active: secondary,
        review: Color(0xFF7D61C4),
        complete: tertiary,
      ),
    ],
  );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class StoreScope extends InheritedNotifier<OperationsStore> {
  const StoreScope({
    super.key,
    required OperationsStore super.notifier,
    required super.child,
  });

  static OperationsStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, 'StoreScope is missing');
    return scope!.notifier!;
  }
}

class OperationsStore extends ChangeNotifier {
  OperationsStore({required this.screenshotMode});

  static const String _recordsKey = 'operations_records_v1';
  static const String _denseKey = 'dense_cards_v1';

  final bool screenshotMode;
  List<WorkRecord> _records = <WorkRecord>[];
  bool _denseCards = false;

  List<WorkRecord> get records => List<WorkRecord>.unmodifiable(_records);
  bool get denseCards => _denseCards;

  Future<void> load() async {
    if (screenshotMode) {
      _records = screenshotRecords();
      _denseCards = false;
      notifyListeners();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _denseCards = prefs.getBool(_denseKey) ?? false;
    final rawRecords = prefs.getString(_recordsKey);
    if (rawRecords != null && rawRecords.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawRecords) as List<dynamic>;
        _records = parsed
            .map((entry) => WorkRecord.fromJson(entry as Map<String, dynamic>))
            .toList();
      } on FormatException {
        _records = <WorkRecord>[];
      } on TypeError {
        _records = <WorkRecord>[];
      }
    }
    notifyListeners();
  }

  Future<void> addRecord(WorkRecord record) async {
    _records = <WorkRecord>[record, ..._records];
    notifyListeners();
    await _persistRecords();
  }

  Future<void> updateRecord(WorkRecord record) async {
    _records = _records
        .map((item) => item.id == record.id ? record : item)
        .toList();
    notifyListeners();
    await _persistRecords();
  }

  Future<void> updateStatus(String id, WorkStatus status) async {
    final record = _records.firstWhere((item) => item.id == id);
    await updateRecord(record.copyWith(status: status));
  }

  Future<void> clearRecords() async {
    _records = <WorkRecord>[];
    notifyListeners();
    if (screenshotMode) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recordsKey);
  }

  Future<void> setDenseCards(bool value) async {
    _denseCards = value;
    notifyListeners();
    if (screenshotMode) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_denseKey, value);
  }

  int countByType(WorkType type) {
    return _records.where((record) => record.type == type).length;
  }

  int countByStatus(WorkStatus status) {
    return _records.where((record) => record.status == status).length;
  }

  Future<void> _persistRecords() async {
    if (screenshotMode) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _records.map((record) => record.toJson()).toList(),
    );
    await prefs.setString(_recordsKey, encoded);
  }
}

enum WorkType { asset, container, reservation, interview }

extension WorkTypeCopy on WorkType {
  String get label {
    switch (this) {
      case WorkType.asset:
        return 'Actif';
      case WorkType.container:
        return 'Conteneur';
      case WorkType.reservation:
        return 'Réservation';
      case WorkType.interview:
        return 'Entretien';
    }
  }

  String get pluralLabel {
    switch (this) {
      case WorkType.asset:
        return 'Actifs';
      case WorkType.container:
        return 'Conteneurs';
      case WorkType.reservation:
        return 'Réservations';
      case WorkType.interview:
        return 'Entretiens';
    }
  }

  IconData get icon {
    switch (this) {
      case WorkType.asset:
        return Icons.inventory_2_outlined;
      case WorkType.container:
        return Icons.local_shipping_outlined;
      case WorkType.reservation:
        return Icons.event_available_outlined;
      case WorkType.interview:
        return Icons.record_voice_over_outlined;
    }
  }
}

enum WorkStatus { planned, active, review, complete }

extension WorkStatusCopy on WorkStatus {
  String get label {
    switch (this) {
      case WorkStatus.planned:
        return 'Planifié';
      case WorkStatus.active:
        return 'En cours';
      case WorkStatus.review:
        return 'À vérifier';
      case WorkStatus.complete:
        return 'Terminé';
    }
  }
}

@immutable
class WorkRecord {
  const WorkRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.reference,
    required this.location,
    required this.owner,
    required this.dueDate,
    required this.status,
    required this.notes,
  });

  final String id;
  final WorkType type;
  final String title;
  final String reference;
  final String location;
  final String owner;
  final String dueDate;
  final WorkStatus status;
  final String notes;

  WorkRecord copyWith({
    WorkType? type,
    String? title,
    String? reference,
    String? location,
    String? owner,
    String? dueDate,
    WorkStatus? status,
    String? notes,
  }) {
    return WorkRecord(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      reference: reference ?? this.reference,
      location: location ?? this.location,
      owner: owner ?? this.owner,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'title': title,
      'reference': reference,
      'location': location,
      'owner': owner,
      'dueDate': dueDate,
      'status': status.name,
      'notes': notes,
    };
  }

  factory WorkRecord.fromJson(Map<String, dynamic> json) {
    return WorkRecord(
      id:
          json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      type: WorkType.values.byName(
        json['type'] as String? ?? WorkType.asset.name,
      ),
      title: json['title'] as String? ?? '',
      reference: json['reference'] as String? ?? '',
      location: json['location'] as String? ?? '',
      owner: json['owner'] as String? ?? '',
      dueDate: json['dueDate'] as String? ?? '',
      status: WorkStatus.values.byName(
        json['status'] as String? ?? WorkStatus.planned.name,
      ),
      notes: json['notes'] as String? ?? '',
    );
  }
}

List<WorkRecord> screenshotRecords() {
  return const <WorkRecord>[
    WorkRecord(
      id: 'shot-asset-1',
      type: WorkType.asset,
      title: 'ASS DE GESTION DE LA BASE DE L',
      reference: 'ACT-2048',
      location: 'Zone loisirs - Local maintenance',
      owner: 'Nadia B.',
      dueDate: '12/05/2026',
      status: WorkStatus.active,
      notes:
          'Contrôle de pression réalisé. Prévoir filtre de rechange avant le prochain week-end.',
    ),
    WorkRecord(
      id: 'shot-container-1',
      type: WorkType.container,
      title: 'Conteneur matériel événementiel',
      reference: 'CTR-17',
      location: 'Quai de service',
      owner: 'Samir H.',
      dueDate: '13/05/2026',
      status: WorkStatus.review,
      notes:
          'Inventaire terminé, deux tables pliantes à rapprocher du planning de réservation.',
    ),
    WorkRecord(
      id: 'shot-reservation-1',
      type: WorkType.reservation,
      title: 'Réservation salle polyvalente',
      reference: 'RSV-592',
      location: 'Pavillon central',
      owner: 'Accueil',
      dueDate: '14/05/2026',
      status: WorkStatus.planned,
      notes:
          'Configuration 34 places, vidéoprojecteur et accès rangement demandés.',
    ),
    WorkRecord(
      id: 'shot-interview-1',
      type: WorkType.interview,
      title: 'Entretien agent saisonnier',
      reference: 'ENT-086',
      location: 'Bureau administratif',
      owner: 'Direction',
      dueDate: '15/05/2026',
      status: WorkStatus.planned,
      notes: 'Créneau validé avec le responsable exploitation.',
    ),
    WorkRecord(
      id: 'shot-asset-2',
      type: WorkType.asset,
      title: 'Kits sécurité nautique',
      reference: 'ACT-2052',
      location: 'Dépôt est',
      owner: 'Yassine M.',
      dueDate: '16/05/2026',
      status: WorkStatus.complete,
      notes: 'Série vérifiée et rangée par tailles.',
    ),
  ];
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.screenshotMode});

  final bool screenshotMode;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _screenshotStep = 0;
  Timer? _screenshotTimer;

  @override
  void initState() {
    super.initState();
    if (widget.screenshotMode) {
      _screenshotTimer = Timer.periodic(const Duration(milliseconds: 2400), (
        _,
      ) {
        if (mounted) {
          setState(() {
            _screenshotStep = (_screenshotStep + 1) % 6;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _screenshotTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = widget.screenshotMode
        ? _indexForStep(_screenshotStep)
        : _index;
    final title = widget.screenshotMode
        ? _titleForStep(_screenshotStep)
        : switch (_index) {
            0 => 'Tableau de bord',
            1 => 'Dossiers',
            2 => 'Planning',
            _ => 'Réglages',
          };

    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: const <Widget>[
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: BrandPill()),
          ),
        ],
      ),
      body: SafeArea(child: _bodyForCurrentState()),
      floatingActionButton: widget.screenshotMode || selectedIndex == 3
          ? null
          : FloatingActionButton.extended(
              key: const Key('new-record'),
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Nouveau'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: widget.screenshotMode
            ? null
            : (value) {
                setState(() => _index = value);
              },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Accueil',
          ),
          NavigationDestination(
            key: Key('nav-records'),
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Dossiers',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Planning',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Réglages',
          ),
        ],
      ),
    );
  }

  Widget _bodyForCurrentState() {
    if (widget.screenshotMode) {
      final store = StoreScope.of(context);
      return switch (_screenshotStep) {
        0 => const OverviewPage(),
        1 => const RecordsPage(initialType: WorkType.container),
        2 => DetailContent(record: store.records[1], embedded: true),
        3 => const RecordFormContent(
          embedded: true,
          initialType: WorkType.reservation,
          initialTitle: 'Réservation espace barbecue',
          initialReference: 'RSV-604',
          initialLocation: 'Aire familles',
          initialOwner: 'Accueil',
          initialDueDate: '17/05/2026',
          initialNotes:
              'Ajouter deux bacs de tri et confirmer l accès portail.',
        ),
        4 => const PlanningPage(),
        _ => const SettingsPage(),
      };
    }

    return IndexedStack(
      index: _index,
      children: const <Widget>[
        OverviewPage(),
        RecordsPage(),
        PlanningPage(),
        SettingsPage(),
      ],
    );
  }

  int _indexForStep(int step) {
    return switch (step) {
      0 => 0,
      1 => 1,
      2 => 1,
      3 => 1,
      4 => 2,
      _ => 3,
    };
  }

  String _titleForStep(int step) {
    return switch (step) {
      0 => 'Tableau de bord',
      1 => 'Conteneurs',
      2 => 'Fiche opération',
      3 => 'Créer une réservation',
      4 => 'Planning',
      _ => 'Réglages',
    };
  }

  void _openForm(BuildContext context) {
    final initialType = _index == 2 ? WorkType.reservation : WorkType.asset;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordFormPage(initialType: initialType),
      ),
    );
  }
}

class BrandPill extends StatelessWidget {
  const BrandPill({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'BASE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final records = store.records;
    final priorityRecords = records
        .where((record) => record.status != WorkStatus.complete)
        .take(3)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      children: <Widget>[
        Text(
          appName,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Suivi local des actifs, conteneurs, réservations et entretiens de la base de loisirs.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.28,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: WorkType.values
              .map(
                (type) => MetricTile(
                  icon: type.icon,
                  label: type.pluralLabel,
                  value: store.countByType(type).toString(),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        Text(
          'Actions rapides',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: WorkType.values
              .map(
                (type) => FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RecordFormPage(initialType: type),
                    ),
                  ),
                  icon: Icon(type.icon),
                  label: Text(type.label),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 22),
        SectionHeader(
          title: 'Priorités du jour',
          actionLabel: '${store.countByStatus(WorkStatus.active)} en cours',
        ),
        const SizedBox(height: 10),
        if (priorityRecords.isEmpty)
          const EmptyState(
            icon: Icons.task_alt_outlined,
            title: 'Aucune priorité enregistrée',
            body:
                'Ajoutez un actif, un conteneur ou une réservation pour organiser la journée.',
          )
        else
          ...priorityRecords.map(
            (record) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RecordCard(record: record),
            ),
          ),
      ],
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key, this.initialType});

  final WorkType? initialType;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  WorkType? _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialType;
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final records = store.records
        .where((record) => _filter == null || record.type == _filter)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      children: <Widget>[
        SectionHeader(
          title: 'Registre opérationnel',
          actionLabel:
              '${records.length} dossier${records.length > 1 ? 's' : ''}',
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('Tous'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
              ),
              ...WorkType.values.map(
                (type) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(type.pluralLabel),
                    avatar: Icon(type.icon, size: 18),
                    selected: _filter == type,
                    onSelected: (_) => setState(() => _filter = type),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (records.isEmpty)
          const EmptyState(
            icon: Icons.assignment_add,
            title: 'Aucun dossier pour ce filtre',
            body: 'Créez un dossier local pour démarrer le suivi.',
          )
        else
          ...records.map(
            (record) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RecordCard(record: record, dense: store.denseCards),
            ),
          ),
      ],
    );
  }
}

class RecordCard extends StatelessWidget {
  const RecordCard({super.key, required this.record, this.dense = false});

  final WorkRecord record;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final statusColor = colorForStatus(context, record.status);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecordDetailPage(recordId: record.id),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(dense ? 10 : 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    record.type.icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            record.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(status: record.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${record.reference} • ${record.location}',
                      maxLines: dense ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (!dense) ...<Widget>[
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.person_outline,
                            size: 16,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              record.owner,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.schedule, size: 16, color: statusColor),
                          const SizedBox(width: 4),
                          Text(record.dueDate),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordDetailPage extends StatelessWidget {
  const RecordDetailPage({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final record = store.records.firstWhere((item) => item.id == recordId);

    return Scaffold(
      appBar: AppBar(title: const Text('Fiche opération')),
      body: SafeArea(child: DetailContent(record: record)),
    );
  }
}

class DetailContent extends StatelessWidget {
  const DetailContent({super.key, required this.record, this.embedded = false});

  final WorkRecord record;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final nextStatus = record.status == WorkStatus.complete
        ? WorkStatus.active
        : WorkStatus.complete;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, embedded ? 8 : 16, 16, 88),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(
                  record.type.icon,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      StatusBadge(status: record.status),
                      Chip(label: Text(record.type.label)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                DetailRow(label: 'Référence', value: record.reference),
                DetailRow(label: 'Lieu', value: record.location),
                DetailRow(label: 'Responsable', value: record.owner),
                DetailRow(label: 'Échéance', value: record.dueDate),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Notes de suivi',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  record.notes.isEmpty
                      ? 'Aucune note enregistrée.'
                      : record.notes,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: embedded
              ? null
              : () => store.updateStatus(record.id, nextStatus),
          icon: Icon(
            record.status == WorkStatus.complete
                ? Icons.restart_alt
                : Icons.task_alt,
          ),
          label: Text(
            record.status == WorkStatus.complete
                ? 'Repasser en cours'
                : 'Marquer comme terminé',
          ),
        ),
      ],
    );
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class RecordFormPage extends StatelessWidget {
  const RecordFormPage({super.key, required this.initialType});

  final WorkType initialType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau dossier')),
      body: SafeArea(child: RecordFormContent(initialType: initialType)),
    );
  }
}

class RecordFormContent extends StatefulWidget {
  const RecordFormContent({
    super.key,
    required this.initialType,
    this.embedded = false,
    this.initialTitle = '',
    this.initialReference = '',
    this.initialLocation = '',
    this.initialOwner = '',
    this.initialDueDate = '',
    this.initialNotes = '',
  });

  final WorkType initialType;
  final bool embedded;
  final String initialTitle;
  final String initialReference;
  final String initialLocation;
  final String initialOwner;
  final String initialDueDate;
  final String initialNotes;

  @override
  State<RecordFormContent> createState() => _RecordFormContentState();
}

class _RecordFormContentState extends State<RecordFormContent> {
  final _formKey = GlobalKey<FormState>();
  late WorkType _type;
  WorkStatus _status = WorkStatus.planned;
  late final TextEditingController _titleController;
  late final TextEditingController _referenceController;
  late final TextEditingController _locationController;
  late final TextEditingController _ownerController;
  late final TextEditingController _dueDateController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _titleController = TextEditingController(text: widget.initialTitle);
    _referenceController = TextEditingController(text: widget.initialReference);
    _locationController = TextEditingController(text: widget.initialLocation);
    _ownerController = TextEditingController(text: widget.initialOwner);
    _dueDateController = TextEditingController(text: widget.initialDueDate);
    _notesController = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _referenceController.dispose();
    _locationController.dispose();
    _ownerController.dispose();
    _dueDateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, widget.embedded ? 8 : 16, 16, 88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Créer un suivi local',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WorkType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type de dossier'),
              items: WorkType.values
                  .map(
                    (type) => DropdownMenuItem<WorkType>(
                      value: type,
                      child: Text(type.label),
                    ),
                  )
                  .toList(),
              onChanged: widget.embedded
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _type = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('field-title'),
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Intitulé'),
              textInputAction: TextInputAction.next,
              validator: requiredField,
              enabled: !widget.embedded,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('field-reference'),
              controller: _referenceController,
              decoration: const InputDecoration(labelText: 'Référence'),
              textInputAction: TextInputAction.next,
              validator: requiredField,
              enabled: !widget.embedded,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('field-location'),
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Lieu'),
              textInputAction: TextInputAction.next,
              validator: requiredField,
              enabled: !widget.embedded,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('field-owner'),
              controller: _ownerController,
              decoration: const InputDecoration(labelText: 'Responsable'),
              textInputAction: TextInputAction.next,
              validator: requiredField,
              enabled: !widget.embedded,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('field-due-date'),
              controller: _dueDateController,
              decoration: const InputDecoration(
                labelText: 'Échéance',
                hintText: 'JJ/MM/AAAA',
              ),
              textInputAction: TextInputAction.next,
              validator: requiredField,
              enabled: !widget.embedded,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WorkStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Statut'),
              items: WorkStatus.values
                  .map(
                    (status) => DropdownMenuItem<WorkStatus>(
                      value: status,
                      child: Text(status.label),
                    ),
                  )
                  .toList(),
              onChanged: widget.embedded
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _status = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('field-notes'),
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              minLines: 3,
              maxLines: 5,
              enabled: !widget.embedded,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('save-record'),
              onPressed: widget.embedded ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer localement'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final record = WorkRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: _type,
      title: _titleController.text.trim(),
      reference: _referenceController.text.trim(),
      location: _locationController.text.trim(),
      owner: _ownerController.text.trim(),
      dueDate: _dueDateController.text.trim(),
      status: _status,
      notes: _notesController.text.trim(),
    );
    await StoreScope.of(context).addRecord(record);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

String? requiredField(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Champ requis';
  }
  return null;
}

class PlanningPage extends StatelessWidget {
  const PlanningPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final records = store.records
        .where(
          (record) =>
              record.type == WorkType.reservation ||
              record.type == WorkType.interview ||
              record.status == WorkStatus.planned,
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      children: <Widget>[
        const SectionHeader(
          title: 'Planning de la base',
          actionLabel: 'Vue locale',
        ),
        const SizedBox(height: 12),
        if (records.isEmpty)
          const EmptyState(
            icon: Icons.calendar_month_outlined,
            title: 'Aucune échéance planifiée',
            body: 'Les réservations et entretiens créés apparaîtront ici.',
          )
        else
          ...records.map(
            (record) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TimelineTile(record: record),
            ),
          ),
      ],
    );
  }
}

class TimelineTile extends StatelessWidget {
  const TimelineTile({super.key, required this.record});

  final WorkRecord record;

  @override
  Widget build(BuildContext context) {
    final statusColor = colorForStatus(context, record.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Column(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(record.type.icon, color: statusColor),
                  ),
                ),
                Container(
                  width: 2,
                  height: 42,
                  color: statusColor.withValues(alpha: 0.28),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.dueDate,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    record.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${record.location} • ${record.owner}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      children: <Widget>[
        const SectionHeader(
          title: 'Réglages et confidentialité',
          actionLabel: 'Local',
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                title: const Text('Cartes compactes'),
                subtitle: const Text(
                  'Réduit la hauteur des dossiers dans le registre.',
                ),
                value: store.denseCards,
                onChanged: store.setDenseCards,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Données sur cet appareil'),
                subtitle: Text(
                  '${store.records.length} dossier(s) enregistrés localement',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Vider les dossiers locaux'),
                subtitle: const Text(
                  'Supprime uniquement les dossiers de cette application.',
                ),
                onTap: store.records.isEmpty ? null : store.clearRecords,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Confidentialité',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Aucun compte, aucune synchronisation et aucune collecte analytique. Les dossiers restent dans le stockage local de l application.',
                ),
                const SizedBox(height: 12),
                Text(
                  companyName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(supportEmail),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.actionLabel,
  });

  final String title;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.secondary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              actionLabel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final WorkStatus status;

  @override
  Widget build(BuildContext context) {
    final color = colorForStatus(context, status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          status.label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.planned,
    required this.active,
    required this.review,
    required this.complete,
  });

  final Color planned;
  final Color active;
  final Color review;
  final Color complete;

  @override
  StatusColors copyWith({
    Color? planned,
    Color? active,
    Color? review,
    Color? complete,
  }) {
    return StatusColors(
      planned: planned ?? this.planned,
      active: active ?? this.active,
      review: review ?? this.review,
      complete: complete ?? this.complete,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) {
      return this;
    }

    return StatusColors(
      planned: Color.lerp(planned, other.planned, t)!,
      active: Color.lerp(active, other.active, t)!,
      review: Color.lerp(review, other.review, t)!,
      complete: Color.lerp(complete, other.complete, t)!,
    );
  }
}

Color colorForStatus(BuildContext context, WorkStatus status) {
  final colors = Theme.of(context).extension<StatusColors>()!;
  return switch (status) {
    WorkStatus.planned => colors.planned,
    WorkStatus.active => colors.active,
    WorkStatus.review => colors.review,
    WorkStatus.complete => colors.complete,
  };
}
