// Paged lists and their parts. Owned by AppWand.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'api_client.dart' show errorMessage;
import 'i18n.dart';
import 'icons.dart';
import 'theme.dart' show AppStyle, ListRowStyle, ListScroll, appStyle, listRowGap, listRowStyle, listScroll;
import 'widgets.dart' show AppSurface, EmptyView, ErrorView, LoadingView, showConfirmDialog;

export 'theme.dart' show ListRowStyle, ListScroll;

/// How a PagedList moves through the pages of a list answer.
enum Paging {
  /// A "Load more" button under the rows.
  loadMore,

  /// More rows load by themselves as the list nears its end.
  infinite,

  /// One page of rows at a time, with page arrows under them.
  pages,
}

/// Rows one under another, or cards in a grid.
enum ListLayout { list, grid }

/// One column of a PagedList shown as a table (PagedList.columns).
class TableColumn {
  const TableColumn({
    required this.label,
    required this.cell,
    this.sortKey,
    this.numeric = false,
    this.flex = 1,
    this.width,
  });

  /// The heading.
  final String label;

  /// What a row shows in this column: a Text (kept to one line), or a small
  /// widget such as a chip or a picture.
  final Widget Function(BuildContext context, Map<String, dynamic> row) cell;

  /// The column the API sorts by when the heading is clicked; null for a
  /// column that cannot be sorted.
  final String? sortKey;

  /// Right-aligned, for amounts and counts.
  final bool numeric;

  /// The share of the spare width this column takes.
  final int flex;

  /// A fixed width in place of [flex], for short cells (a date, a status).
  final double? width;

  double get _minWidth => width ?? 120.0 * flex;
}

/// A page's own way of setting its list rows apart, in place of the app's
/// (theme.dart's listRowStyle and listRowGap). Set in AppWand: router.g.dart
/// wraps the page in it, and PagedList reads it. Pages never use it.
class ListRows extends InheritedWidget {
  const ListRows({super.key, required this.style, required this.gap, required super.child});
  final ListRowStyle style;
  final double gap;

  static ListRows? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ListRows>();

  @override
  bool updateShouldNotify(ListRows oldWidget) => style != oldWidget.style || gap != oldWidget.gap;
}

/// A page's own way of scrolling its list, in place of the app's (theme.dart's
/// listScroll). Set in AppWand: router.g.dart wraps the page in it, and
/// PagedList reads it. Pages never use it.
class ListPhysics extends InheritedWidget {
  const ListPhysics({super.key, required this.scroll, required super.child});
  final ListScroll scroll;

  static ListPhysics? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ListPhysics>();

  /// The physics of a list under [context]. Always scrollable, so a short
  /// list can still be pulled to refresh.
  static ScrollPhysics of(BuildContext context) {
    switch (maybeOf(context)?.scroll ?? listScroll) {
      case ListScroll.bouncing:
        return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
      case ListScroll.clamping:
        return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
      case ListScroll.platform:
        return const AlwaysScrollableScrollPhysics();
    }
  }

  @override
  bool updateShouldNotify(ListPhysics oldWidget) => scroll != oldWidget.scroll;
}

/// Lets a page reload a PagedList or take rows out of it.
class PagedListController {
  _PagedListState? _state;

  /// The rows loaded so far.
  List<Map<String, dynamic>> get items => List.unmodifiable(_state?._items ?? const <Map<String, dynamic>>[]);

  /// How many rows the API has in all.
  int get total => _state?._total ?? 0;

  /// Loads the rows again (the current page, with Paging.pages).
  Future<void> refresh() => _state?.refresh() ?? Future<void>.value();

  /// Takes the rows whose 'id' is in [ids] out of the list, e.g. after a delete.
  void remove(Iterable<Object?> ids) => _state?.remove(ids);
}

/// A scrolling list of rows from the API that loads its pages and draws its
/// own loading, error, empty and paging states.
class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.query = '',
    this.paging = Paging.loadMore,
    this.pageSize = 20,
    this.refreshable = true,
    this.skeleton = false,
    this.layout = ListLayout.list,
    this.gridItemBuilder,
    this.gridItemHeight = 220,
    this.columns,
    this.onRowTap,
    this.rowActions,
    this.rowActionsWidth = 96,
    this.sort,
    this.order = 'asc',
    this.onSort,
    this.tableBreakpoint = 840,
    this.controller,
    this.selection,
    this.emptyMessage,
    this.emptyIcon = AppIcons.inbox,
    this.padding = const EdgeInsets.only(bottom: 88),
  });

  /// Loads one page (1-based) of [limit] rows; returns the API's
  /// { items, total } answer as it is (a plain List works too).
  final Future<dynamic> Function(int page, int limit) fetch;
  final Widget Function(BuildContext context, Map<String, dynamic> row) itemBuilder;

  /// Everything [fetch] sends besides the page (search, sort, filters) as one
  /// String; when it changes the list starts again from page 1.
  final String query;
  final Paging paging;
  final int pageSize;

  /// Pull to refresh.
  final bool refreshable;

  /// Shimmering placeholders instead of a spinner while the first page loads.
  final bool skeleton;
  final ListLayout layout;

  /// The card for a row in the grid layout; [itemBuilder] when null.
  final Widget Function(BuildContext context, Map<String, dynamic> row)? gridItemBuilder;
  final double gridItemHeight;

  /// The data table: with columns, the list layout is drawn as a table once
  /// the list is [tableBreakpoint] wide (web, desktop, tablets), with a
  /// heading row that stays in place and numbered pages whatever [paging]
  /// is. Narrower, and in the grid layout, nothing changes.
  final List<TableColumn>? columns;

  /// What clicking a table row does (open the record).
  final void Function(Map<String, dynamic> row)? onRowTap;

  /// The buttons at the end of a table row (edit, delete).
  final List<Widget> Function(BuildContext context, Map<String, dynamic> row)? rowActions;

  /// The width kept for [rowActions]: 48 for each button.
  final double rowActionsWidth;

  /// The column and direction ('asc' or 'desc') the rows are sorted by, shown
  /// in the table's headings; [onSort] is told when a heading is clicked.
  final String? sort;
  final String order;
  final void Function(String sort, String order)? onSort;
  final double tableBreakpoint;
  final PagedListController? controller;

  /// Rows rebuild when it changes, so they can show what is selected. The
  /// table adds a checkbox column for it.
  final SelectionController? selection;
  /// "Nothing here yet." (in the app's language) when not given.
  final String? emptyMessage;
  final IconData emptyIcon;

  /// Space after the last row, clear of a floating action button.
  final EdgeInsetsGeometry padding;

  @override
  State<PagedList> createState() => _PagedListState();
}

class _PagedListState extends State<PagedList> {
  final List<Map<String, dynamic>> _items = [];
  final ScrollController _scroll = ScrollController();
  final ScrollController _sideways = ScrollController();
  int _total = 0;

  /// The page shown last (with Paging.pages) or loaded last.
  int _page = 1;

  /// Whether [_items] holds an answer, rather than nothing yet.
  bool _loaded = false;
  bool _busy = false;

  /// Loading while the rows of an earlier answer are still shown.
  bool _reloading = false;
  Object? _error;

  /// Bumped when the list starts over, so an older answer is thrown away.
  int _generation = 0;

  /// Whether the rows are drawn as a table; set while building, from the width.
  bool _asTable = false;

  /// The rows per page picked under the table; [PagedList.pageSize] when null.
  int? _rowsPerPage;

  /// A table always moves by numbered pages.
  Paging get _paging => _asTable ? Paging.pages : widget.paging;

  int get _pageSize => _asTable ? _rowsPerPage ?? widget.pageSize : widget.pageSize;

  bool get _hasMore => _items.length < _total;

  int get _pageCount => math.max(1, (_total / _pageSize).ceil());

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _scroll.addListener(_onScroll);
    _load(1);
  }

  @override
  void didUpdateWidget(PagedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) oldWidget.controller?._state = null;
      widget.controller?._state = this;
    }
    if (oldWidget.query != widget.query || oldWidget.paging != widget.paging || oldWidget.pageSize != widget.pageSize) {
      _generation++;
      _reloading = _loaded;
      _load(1);
      // The selection belongs to rows that may be gone; cleared after this
      // build, as listeners outside the list rebuild with it.
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) => widget.selection?.clear());
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _scroll.dispose();
    _sideways.dispose();
    super.dispose();
  }

  Future<void> refresh() {
    _generation++;
    widget.selection?.clear();
    setState(() => _reloading = _loaded);
    return _load(_paging == Paging.pages ? _page : 1);
  }

  /// Starts again from page 1, keeping the rows shown until the answer comes.
  void _restart() {
    _generation++;
    setState(() => _reloading = _loaded);
    _load(1);
  }

  /// Follows a switch between the table and the list. The rows are loaded
  /// again when they are not simply one page of the other's size.
  void _setTable(bool table) {
    if (table == _asTable) return;
    final size = _pageSize;
    final stale = widget.paging != Paging.pages && (_page > 1 || (_busy && _loaded));
    _asTable = table;
    if (!stale && _pageSize == size) return;
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (mounted) _restart();
    });
  }

  void _setRowsPerPage(int rows) {
    if (rows == _pageSize) return;
    _rowsPerPage = rows;
    _goTo(1);
  }

  void remove(Iterable<Object?> ids) {
    final gone = ids.toSet();
    final before = _items.length;
    setState(() {
      _items.removeWhere((row) => gone.contains(row['id']));
      _total = math.max(0, _total - (before - _items.length));
    });
    _fillViewport();
  }

  Future<void> _load(int page, {bool append = false}) async {
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.fetch(page, _pageSize);
      if (!mounted || generation != _generation) return;
      final rows = _rowsOf(data);
      // A page emptied by deletes elsewhere: show the one before it.
      if (!append && rows.isEmpty && page > 1 && _paging == Paging.pages) {
        _page = page - 1;
        return _load(page - 1);
      }
      setState(() {
        if (!append) _items.clear();
        _items.addAll(rows);
        _total = _totalOf(data) ?? _items.length;
        _page = page;
        _loaded = true;
        _busy = false;
        _reloading = false;
      });
      _fillViewport();
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _busy = false;
        _reloading = false;
      });
    }
  }

  static List<Map<String, dynamic>> _rowsOf(dynamic data) {
    final raw = data is Map ? data['items'] : data;
    if (raw is! List) return [];
    return [for (final row in raw) if (row is Map) Map<String, dynamic>.from(row)];
  }

  static int? _totalOf(dynamic data) => data is Map ? int.tryParse('${data['total']}') : null;

  void _loadMore() {
    if (_busy || _error != null || !_hasMore) return;
    _load(_page + 1, append: true);
  }

  void _goTo(int page) {
    _generation++;
    setState(() {
      _loaded = false;
      _items.clear();
      _page = page;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load(page);
  }

  void _retry() {
    if (!_loaded) {
      refresh();
    } else if (_paging == Paging.pages) {
      _goTo(_page);
    } else {
      setState(() => _error = null);
      _loadMore();
    }
  }

  void _onScroll() {
    if (_paging == Paging.infinite && _scroll.position.extentAfter < 500) _loadMore();
  }

  /// Keeps loading while the rows do not fill the screen, so infinite scroll
  /// has something to scroll.
  void _fillViewport() {
    if (_paging != Paging.infinite) return;
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (mounted && _scroll.hasClients && _scroll.position.extentAfter < 500) _loadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.columns == null) {
      _setTable(false);
      return _listView(context);
    }
    return LayoutBuilder(builder: (context, constraints) {
      _setTable(widget.layout == ListLayout.list && constraints.maxWidth >= widget.tableBreakpoint);
      return _asTable ? _tableView(context, constraints.maxWidth) : _listView(context);
    });
  }

  Widget _listView(BuildContext context) {
    final selection = widget.selection;
    Widget view = selection == null
        ? _scrollView(context)
        : ListenableBuilder(listenable: selection, builder: (context, child) => _scrollView(context));
    if (widget.refreshable) view = RefreshIndicator(onRefresh: refresh, child: view);
    return view;
  }

  Widget _tableView(BuildContext context, double maxWidth) {
    final selection = widget.selection;
    return selection == null
        ? _table(context, maxWidth)
        : ListenableBuilder(listenable: selection, builder: (context, child) => _table(context, maxWidth));
  }

  /// The rows as a table in an AppSurface: the headings, the rows scrolling
  /// under them, and the pages along the bottom. A table too narrow for its
  /// columns scrolls sideways.
  Widget _table(BuildContext context, double maxWidth) {
    final columns = widget.columns!;
    final scheme = Theme.of(context).colorScheme;
    final inner = maxWidth - 32;
    final minWidth = columns.fold<double>(16, (sum, column) => sum + column._minWidth) +
        (widget.selection != null ? 48 : 0) +
        (widget.rowActions != null ? widget.rowActionsWidth : 0);
    final line = Divider(height: 1, thickness: 1, color: scheme.outlineVariant);

    Widget rows = CustomScrollView(
      controller: _scroll,
      physics: ListPhysics.of(context),
      slivers: [
        if (!_loaded && _error != null)
          SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: errorMessage(_error!), onRetry: _retry))
        else if (!_loaded && widget.skeleton)
          SliverToBoxAdapter(child: _tableSkeleton(columns))
        else if (!_loaded)
          const SliverFillRemaining(hasScrollBody: false, child: LoadingView())
        else if (_items.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: EmptyView(message: widget.emptyMessage ?? tr('Nothing here yet.'), icon: widget.emptyIcon))
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _tableRow(context, columns, _items[index]),
              childCount: _items.length,
            ),
          ),
      ],
    );
    if (widget.refreshable) rows = RefreshIndicator(onRefresh: refresh, child: rows);

    Widget grid = Column(children: [
      _tableHeader(context, columns),
      line,
      if (_reloading) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: rows),
    ]);
    if (minWidth > inner) {
      // A scrollbar that stays in view: a mouse cannot drag the table, and
      // Flutter gives sideways scrolling none of its own. The rows end above it.
      grid = Scrollbar(
        controller: _sideways,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _sideways,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minWidth,
            child: Padding(padding: const EdgeInsets.only(bottom: 12), child: grid),
          ),
        ),
      );
    }
    // Clipped to the surface's corners, inside Brutalism's border.
    final shape = Theme.of(context).cardTheme.shape;
    return AppSurface(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: EdgeInsets.all(appStyle == AppStyle.brutalism ? 2.5 : 0),
      child: ClipRRect(
        borderRadius: shape is RoundedRectangleBorder ? shape.borderRadius : BorderRadius.circular(12),
        child: Column(children: [Expanded(child: grid), line, _tableFooter(context, inner)]),
      ),
    );
  }

  /// A cell of the table, as wide in every row as in the headings.
  Widget _tableCell(TableColumn column, Widget child) {
    final cell = Padding(
      padding: const EdgeInsets.all(8),
      child: Align(
        heightFactor: 1,
        alignment: column.numeric ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: child,
      ),
    );
    final width = column.width;
    return width != null ? SizedBox(width: width, child: cell) : Expanded(flex: column.flex, child: cell);
  }

  Widget _tableHeader(BuildContext context, List<TableColumn> columns) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selection = widget.selection;
    final style = theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600);
    final ids = [for (final row in _items) row['id']];
    final picked = selection == null ? 0 : ids.where(selection.isSelected).length;
    final all = ids.isNotEmpty && picked == ids.length;
    return Material(
      color: scheme.surfaceContainerHighest.withAlpha(110),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          if (selection != null)
            SizedBox(
              width: 48,
              child: Checkbox(
                tristate: true,
                value: all ? true : picked == 0 ? false : null,
                onChanged: ids.isEmpty ? null : (value) => all ? selection.clear() : selection.selectAll(ids),
              ),
            ),
          for (final column in columns) _tableCell(column, _heading(context, column, style)),
          if (widget.rowActions != null) SizedBox(width: widget.rowActionsWidth),
        ]),
      ),
    );
  }

  /// A column's heading; one with a sortKey sorts by it, and flips the order
  /// when it is the current one.
  Widget _heading(BuildContext context, TableColumn column, TextStyle? style) {
    final label = Text(column.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    final key = column.sortKey;
    final onSort = widget.onSort;
    if (key == null || onSort == null) return label;
    final scheme = Theme.of(context).colorScheme;
    final active = key == widget.sort;
    final ascending = widget.order == 'asc';
    return Tooltip(
      message: tr('Sort by {column}', {'column': column.label}),
      child: InkWell(
        onTap: () => onSort(key, active && ascending ? 'desc' : 'asc'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: label),
            const SizedBox(width: 4),
            Icon(
              active ? (ascending ? AppIcons.arrowUp : AppIcons.arrowDown) : AppIcons.sort,
              size: 16,
              color: active ? scheme.primary : scheme.outline,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tableRow(BuildContext context, List<TableColumn> columns, Map<String, dynamic> row) {
    final scheme = Theme.of(context).colorScheme;
    final selection = widget.selection;
    final onRowTap = widget.onRowTap;
    final rowActions = widget.rowActions;
    final selected = selection?.isSelected(row['id']) ?? false;
    return Material(
      color: selected ? scheme.secondaryContainer.withAlpha(120) : Colors.transparent,
      child: InkWell(
        onTap: onRowTap == null ? null : () => onRowTap(row),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
          child: Row(children: [
            if (selection != null)
              SizedBox(
                width: 48,
                child: Checkbox(value: selected, onChanged: (value) => selection.toggle(row['id'])),
              ),
            for (final column in columns)
              _tableCell(
                column,
                DefaultTextStyle.merge(maxLines: 1, overflow: TextOverflow.ellipsis, child: column.cell(context, row)),
              ),
            if (rowActions != null)
              SizedBox(
                width: widget.rowActionsWidth,
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: rowActions(context, row)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _tableSkeleton(List<TableColumn> columns) {
    return Skeleton(
      child: Column(children: [
        for (var i = 0; i < 8; i++)
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              if (widget.selection != null) const SizedBox(width: 48),
              for (var c = 0; c < columns.length; c++)
                _tableCell(
                  columns[c],
                  FractionallySizedBox(widthFactor: 0.4 + ((i + c) * 3 % 5) / 10, child: const SkeletonBox()),
                ),
              if (widget.rowActions != null) SizedBox(width: widget.rowActionsWidth),
            ]),
          ),
      ]),
    );
  }

  /// The page numbers under a table: the first, the last and those around
  /// the current one, with 0 standing for a gap.
  List<int> _pageNumbers() {
    final shown = <int>{
      1,
      _pageCount,
      for (var page = _page - 1; page <= _page + 1; page++)
        if (page >= 1 && page <= _pageCount) page,
    }.toList()
      ..sort();
    return [
      for (var i = 0; i < shown.length; i++) ...[
        if (i > 0 && shown[i] - shown[i - 1] > 1) 0,
        shown[i],
      ],
    ];
  }

  /// Under a table: the rows shown, the rows per page and the pages. The end
  /// is left clear for a floating action button.
  Widget _tableFooter(BuildContext context, double width) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final first = (_page - 1) * _pageSize;
    final range = !_loaded
        ? ''
        : _total == 0
            ? tr('No rows')
            : tr('{from}–{to} of {total}', {'from': first + 1, 'to': math.min(first + _items.length, _total), 'total': _total});
    final sizes = <int>{10, 20, 50, 100, widget.pageSize, _pageSize}.toList()..sort();

    Widget arrow(String tooltip, IconData icon, int page) => IconButton(
          tooltip: tooltip,
          onPressed: page >= 1 && page <= _pageCount && !_busy ? () => _goTo(page) : null,
          icon: Icon(icon),
        );
    Widget number(int page) {
      if (page == 0) return Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('…', style: muted));
      final current = page == _page;
      return TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: current ? scheme.secondaryContainer : null,
          foregroundColor: current ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        ),
        onPressed: current || _busy ? () {} : () => _goTo(page),
        child: Text('$page'),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 80, 4),
      child: Row(children: [
        Expanded(child: Text(range, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted)),
        Text(tr('Rows'), style: muted),
        const SizedBox(width: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _pageSize,
            style: theme.textTheme.bodyMedium,
            items: [for (final size in sizes) DropdownMenuItem(value: size, child: Text('$size'))],
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) _setRowsPerPage(value);
                  },
          ),
        ),
        const SizedBox(width: 8),
        arrow(tr('Previous page'), AppIcons.chevronLeft, _page - 1),
        if (width >= 900)
          for (final page in _pageNumbers()) number(page)
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(tr('Page {page} of {pages}', {'page': _page, 'pages': _pageCount}), style: muted),
          ),
        arrow(tr('Next page'), AppIcons.chevronRight, _page + 1),
      ]),
    );
  }

  Widget _scrollView(BuildContext context) {
    return CustomScrollView(
      controller: _scroll,
      physics: ListPhysics.of(context),
      slivers: [
        if (_reloading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
        if (!_loaded && _error != null)
          SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: errorMessage(_error!), onRetry: _retry))
        else if (!_loaded && widget.skeleton)
          _skeletonSliver()
        else if (!_loaded)
          const SliverFillRemaining(hasScrollBody: false, child: LoadingView())
        else if (_items.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: EmptyView(message: widget.emptyMessage ?? tr('Nothing here yet.'), icon: widget.emptyIcon))
        else ...[
          _rowsSliver(),
          SliverToBoxAdapter(child: _footer(context)),
        ],
        SliverPadding(padding: widget.padding),
      ],
    );
  }

  SliverGridDelegate get _gridDelegate => SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: widget.gridItemHeight,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      );

  Widget _rowsSliver() {
    if (widget.layout == ListLayout.grid) {
      final builder = widget.gridItemBuilder ?? widget.itemBuilder;
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        sliver: SliverGrid(
          gridDelegate: _gridDelegate,
          delegate: SliverChildBuilderDelegate((context, index) => builder(context, _items[index]), childCount: _items.length),
        ),
      );
    }
    // The rows are set apart as the page is set to (ListRows), or else the
    // app (theme.dart's listRowStyle and listRowGap): a line, a card each,
    // or only the gap.
    final own = ListRows.maybeOf(context);
    final rowStyle = own?.style ?? listRowStyle;
    final rowGap = own?.gap ?? listRowGap;
    final theme = Theme.of(context);
    final brutal = appStyle == AppStyle.brutalism;
    switch (rowStyle) {
      case ListRowStyle.card:
        // Clipped to the card's corners, inside Brutalism's border, so a
        // row's ink and its swipe backgrounds stay in the card.
        final shape = theme.cardTheme.shape;
        final radius = shape is RoundedRectangleBorder ? shape.borderRadius : BorderRadius.circular(12);
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList.separated(
            itemCount: _items.length,
            itemBuilder: (context, index) => AppSurface(
              padding: EdgeInsets.all(brutal ? 2.5 : 0),
              child: ClipRRect(borderRadius: radius, child: widget.itemBuilder(context, _items[index])),
            ),
            separatorBuilder: (context, index) => SizedBox(height: rowGap),
          ),
        );
      case ListRowStyle.divider:
        final thickness = brutal ? 2.0 : 1.0;
        final line = Divider(
          height: rowGap + thickness,
          thickness: thickness,
          indent: 16,
          endIndent: 16,
          color: brutal ? theme.colorScheme.outline : theme.colorScheme.outlineVariant,
        );
        return SliverList.separated(
          itemCount: _items.length,
          itemBuilder: (context, index) => widget.itemBuilder(context, _items[index]),
          separatorBuilder: (context, index) => line,
        );
      case ListRowStyle.none:
        return SliverList.separated(
          itemCount: _items.length,
          itemBuilder: (context, index) => widget.itemBuilder(context, _items[index]),
          separatorBuilder: (context, index) => SizedBox(height: rowGap),
        );
    }
  }

  Widget _skeletonSliver() {
    if (widget.layout == ListLayout.grid) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        sliver: SliverGrid(
          gridDelegate: _gridDelegate,
          delegate: SliverChildBuilderDelegate((context, index) => const SkeletonCard(), childCount: 6),
        ),
      );
    }
    return const SliverToBoxAdapter(child: SkeletonList());
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    const spinner = SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3));
    final Widget child;
    if (_error != null) {
      child = Column(mainAxisSize: MainAxisSize.min, children: [
        Text(errorMessage(_error!), textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _retry, icon: const Icon(AppIcons.refresh), label: Text(tr('Try again'))),
      ]);
    } else {
      switch (_paging) {
        case Paging.infinite:
          child = _busy ? spinner : _hasMore ? const SizedBox(height: 28) : Text(tr('All {total} shown', {'total': _total}), style: muted);
        case Paging.loadMore:
          child = Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Showing {count} of {total}', {'count': _items.length, 'total': _total}), style: muted),
            if (_hasMore) ...[
              const SizedBox(height: 8),
              _busy ? spinner : OutlinedButton(onPressed: _loadMore, child: Text(tr('Load more'))),
            ],
          ]);
        case Paging.pages:
          child = Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: tr('Previous page'),
              onPressed: _page > 1 && !_busy ? () => _goTo(_page - 1) : null,
              icon: const Icon(AppIcons.chevronLeft),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(tr('Page {page} of {pages}', {'page': _page, 'pages': _pageCount}), style: muted),
            ),
            IconButton(
              tooltip: tr('Next page'),
              onPressed: _page < _pageCount && !_busy ? () => _goTo(_page + 1) : null,
              icon: const Icon(AppIcons.chevronRight),
            ),
          ]);
      }
    }
    return Padding(padding: const EdgeInsets.all(16), child: Center(child: child));
  }
}

/// The page's app bar actions on a phone whose bar has no room for them.
/// AppScaffold puts it around the page, and the page's ListSearchField shows
/// them beside the search box; pages never use it themselves.
class PageActions extends InheritedWidget {
  const PageActions({super.key, required this.actions, required this.claims, required super.child});

  /// Empty while the app bar keeps them.
  final List<Widget> actions;

  /// How many search boxes are showing them.
  final ValueNotifier<int> claims;

  static PageActions? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PageActions>();

  @override
  bool updateShouldNotify(PageActions oldWidget) => true;
}

/// What a page's search box and its filter bar share, so that on a wide
/// screen they are one row: the filters, then the search box at the end.
/// Kept per page (its Scaffold); pages never use it themselves.
class _ListBar {
  static final Expando<_ListBar> _bars = Expando<_ListBar>();

  static _ListBar? of(BuildContext context) {
    final page = Scaffold.maybeOf(context);
    if (page == null) return null;
    return _bars[page] ??= _ListBar();
  }

  /// From this width the search box holds the filters beside it.
  static const double breakpoint = 720;

  /// The search box's width while it does.
  static const double searchWidth = 320;

  /// How many search boxes are wide enough to hold the filters.
  final ValueNotifier<int> hosts = ValueNotifier(0);

  /// The filter bar's chips, while a search box holds them.
  final ValueNotifier<Widget?> filters = ValueNotifier(null);
}

/// The search box over a list. It reports once typing pauses, so the list
/// reloads once per search rather than once per key. On a phone it also
/// holds the page's actions that did not fit in the app bar; on a wide
/// screen it holds the page's FilterBar, and keeps a fixed width at the end.
class ListSearchField extends StatefulWidget {
  const ListSearchField({super.key, required this.onChanged, this.hint, this.initialValue = ''});
  final ValueChanged<String> onChanged;

  /// "Search" (in the app's language) when not given.
  final String? hint;
  final String initialValue;

  @override
  State<ListSearchField> createState() => _ListSearchFieldState();
}

class _ListSearchFieldState extends State<ListSearchField> {
  late final TextEditingController _text = TextEditingController(text: widget.initialValue);
  Timer? _timer;

  // The page whose actions this box is showing, told so it drops its own row.
  ValueNotifier<int>? _claimed;

  // The page's bar, and whether this box is wide enough to hold its filters.
  _ListBar? _bar;
  bool _hosting = false;

  void _host(bool wide) {
    if (wide == _hosting) return;
    _hosting = wide;
    final bar = _bar;
    if (bar == null) return;
    // After the frame: the filter bar is being built too.
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) => bar.hosts.value += wide ? 1 : -1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bar ??= _ListBar.of(context);
    final scope = PageActions.of(context);
    final next = scope != null && scope.actions.isNotEmpty ? scope.claims : null;
    if (identical(next, _claimed)) return;
    final previous = _claimed;
    _claimed = next;
    // After the frame: the page's scaffold is being built too.
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (previous != null) previous.value--;
      if (next != null) next.value++;
    });
  }

  @override
  void dispose() {
    final claimed = _claimed;
    if (claimed != null) WidgetsBinding.instance.addPostFrameCallback((timeStamp) => claimed.value--);
    _host(false);
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), () => widget.onChanged(value.trim()));
  }

  void _submit(String value) {
    _timer?.cancel();
    widget.onChanged(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final actions = PageActions.of(context)?.actions ?? const <Widget>[];
    final field = TextField(
      controller: _text,
      textInputAction: TextInputAction.search,
      onChanged: _changed,
      onSubmitted: _submit,
      decoration: InputDecoration(
        hintText: widget.hint ?? tr('Search'),
        prefixIcon: const Icon(AppIcons.search),
        suffixIcon: _text.text.isEmpty
            ? null
            : IconButton(
                tooltip: tr('Clear'),
                icon: const Icon(AppIcons.close),
                onPressed: () {
                  _text.clear();
                  setState(() {});
                  _submit('');
                },
              ),
      ),
    );
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16, 12, actions.isEmpty ? 16 : 8, 4),
      // The box keeps 140 at least; more actions than fit beside it scroll.
      child: LayoutBuilder(builder: (context, box) {
        final bar = _bar;
        final wide = bar != null && actions.isEmpty && box.maxWidth >= _ListBar.breakpoint;
        _host(wide);
        final narrow = Row(children: [
          Expanded(child: field),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: math.max(0.0, box.maxWidth - 144)),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ),
          ],
        ]);
        if (!wide) return narrow;
        // The page's filters first, the box at the end at its own width.
        return ListenableBuilder(
          listenable: bar.filters,
          builder: (context, child) {
            final filters = bar.filters.value;
            return Row(children: [
              Expanded(child: filters ?? const SizedBox.shrink()),
              const SizedBox(width: 12),
              SizedBox(width: _ListBar.searchWidth, child: field),
            ]);
          },
        );
      }),
    );
  }
}

/// A row that swipes towards the start to delete (after asking) and towards
/// the end to edit. Use it inside PagedList's itemBuilder: a row deleted
/// this way leaves the list by itself.
class SwipeTile extends StatelessWidget {
  const SwipeTile({
    super.key,
    required this.id,
    required this.child,
    this.onDelete,
    this.onEdit,
    this.confirmTitle,
    this.confirmMessage,
  });

  /// The row's 'id'.
  final Object id;
  final Widget child;

  /// Deletes the row through the API: true when it was deleted, false (after
  /// showing why) when not.
  final Future<bool> Function()? onDelete;
  final VoidCallback? onEdit;
  /// "Delete this item?" and "This cannot be undone." (in the app's
  /// language) when not given.
  final String? confirmTitle;
  final String? confirmMessage;

  Widget _background(Color color, Color foreground, IconData icon, String label, Alignment alignment) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: foreground),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onDelete = this.onDelete;
    final onEdit = this.onEdit;
    if (onDelete == null && onEdit == null) return child;
    final scheme = Theme.of(context).colorScheme;
    final edit = _background(scheme.primaryContainer, scheme.onPrimaryContainer, AppIcons.edit, tr('Edit'), Alignment.centerLeft);
    final delete = _background(scheme.errorContainer, scheme.onErrorContainer, AppIcons.delete, tr('Delete'), Alignment.centerRight);
    return Dismissible(
      key: ValueKey<String>('swipe-$id'),
      direction: onDelete != null && onEdit != null
          ? DismissDirection.horizontal
          : onDelete != null
              ? DismissDirection.endToStart
              : DismissDirection.startToEnd,
      background: onEdit != null ? edit : delete,
      secondaryBackground: onEdit != null && onDelete != null ? delete : null,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onEdit?.call();
          return false;
        }
        if (onDelete == null) return false;
        if (!await showConfirmDialog(context, title: confirmTitle ?? tr('Delete this item?'), message: confirmMessage ?? tr('This cannot be undone.'))) return false;
        return onDelete();
      },
      onDismissed: (direction) => context.findAncestorStateOfType<_PagedListState>()?.remove([id]),
      child: child,
    );
  }
}

/// The rows picked on a list, by their 'id'. Long-pressing a row starts a
/// selection; while one is active, tapping a row toggles it.
class SelectionController extends ChangeNotifier {
  final Set<Object> _ids = {};

  Set<Object> get ids => Set.unmodifiable(_ids);
  int get count => _ids.length;
  bool get active => _ids.isNotEmpty;

  bool isSelected(Object? id) => _ids.contains(id);

  void toggle(Object? id) {
    if (id == null) return;
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
  }

  void selectAll(Iterable<Object?> ids) {
    _ids.addAll(ids.whereType<Object>());
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }
}

/// The bar over a list while rows are selected: the count, Select all, the
/// page's actions (e.g. Delete) and a button that ends the selection.
class SelectionBar extends StatelessWidget {
  const SelectionBar({super.key, required this.controller, this.onSelectAll, this.actions = const []});
  final SelectionController controller;
  final VoidCallback? onSelectAll;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: !controller.active
            ? const SizedBox(width: double.infinity)
            : Material(
                color: scheme.secondaryContainer,
                child: IconTheme.merge(
                  data: IconThemeData(color: scheme.onSecondaryContainer),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(children: [
                      IconButton(tooltip: tr('Clear selection'), onPressed: controller.clear, icon: const Icon(AppIcons.close)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          tr('{count} selected', {'count': controller.count}),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (onSelectAll != null) TextButton(onPressed: onSelectAll, child: Text(tr('Select all'))),
                      ...actions,
                    ]),
                  ),
                ),
              ),
      ),
    );
  }
}

/// One filter of a FilterBar: the query key the API reads, its label and its
/// options (the value sent → the label shown).
class ListFilter {
  const ListFilter({required this.field, required this.label, required this.options});
  final String field;
  final String label;
  final Map<String, String> options;
}

/// A row of filter chips under a list's search field. [values] maps a
/// filter's field to the value chosen; a filter left out means any.
/// [trailing] is the page's other filter controls (a date range button),
/// after the chips. On a wide screen the row sits beside the search box
/// (ListSearchField shows it) instead of under it.
class FilterBar extends StatefulWidget {
  const FilterBar({
    super.key,
    required this.filters,
    required this.values,
    required this.onChanged,
    this.trailing = const [],
  });
  final List<ListFilter> filters;
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onChanged;
  final List<Widget> trailing;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  _ListBar? _bar;

  // The row last handed to the page's search box.
  Widget? _handed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bar ??= _ListBar.of(context);
  }

  @override
  void dispose() {
    _hand(null);
    super.dispose();
  }

  void _hand(Widget? row) {
    final bar = _bar;
    if (bar == null || (row == null && _handed == null)) return;
    final previous = _handed;
    _handed = row;
    // After the frame: the search box is being built too. Another filter
    // bar's row is left alone.
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      if (row != null || identical(bar.filters.value, previous)) bar.filters.value = row;
    });
  }

  void _set(String field, String? value) {
    final next = Map<String, String>.of(widget.values);
    if (value == null) {
      next.remove(field);
    } else {
      next[field] = value;
    }
    widget.onChanged(next);
  }

  Widget _row(EdgeInsets padding) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final filter in widget.filters)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _FilterChip(filter: filter, value: widget.values[filter.field], onSelected: (value) => _set(filter.field, value)),
            ),
          for (final extra in widget.trailing) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: extra),
          if (widget.values.isNotEmpty) TextButton(onPressed: () => widget.onChanged(<String, String>{}), child: Text(tr('Clear'))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bar = _bar;
    final empty = widget.filters.isEmpty && widget.trailing.isEmpty;
    if (bar == null || empty) {
      _hand(null);
      return empty ? const SizedBox.shrink() : _row(const EdgeInsets.symmetric(horizontal: 16, vertical: 8));
    }
    return ValueListenableBuilder<int>(
      valueListenable: bar.hosts,
      builder: (context, hosts, child) {
        // A wide search box shows the row beside it.
        final held = hosts > 0;
        _hand(held ? _row(EdgeInsets.zero) : null);
        return held ? const SizedBox(width: double.infinity) : _row(const EdgeInsets.symmetric(horizontal: 16, vertical: 8));
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.filter, required this.value, required this.onSelected});
  final ListFilter filter;
  final String? value;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(value == null ? AppIcons.check : null),
          onPressed: () => onSelected(null),
          child: Text(tr('Any')),
        ),
        for (final option in filter.options.entries)
          MenuItemButton(
            leadingIcon: Icon(value == option.key ? AppIcons.check : null),
            onPressed: () => onSelected(option.key),
            child: Text(option.value),
          ),
      ],
      builder: (context, controller, child) => FilterChip(
        label: Text(value == null ? filter.label : '${filter.label}: ${filter.options[value] ?? value}'),
        selected: value != null,
        showCheckmark: false,
        onDeleted: value == null ? null : () => onSelected(null),
        onSelected: filter.options.isEmpty ? null : (selected) => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// An app-bar button that picks the column a list is sorted by. [fields]
/// maps a column to its label; picking the current column again flips
/// [order] between 'asc' and 'desc'.
class SortMenu extends StatelessWidget {
  const SortMenu({super.key, required this.fields, required this.sort, required this.order, required this.onChanged});
  final Map<String, String> fields;
  final String sort;
  final String order;
  final void Function(String sort, String order) onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tr('Sort'),
      icon: const Icon(AppIcons.sort),
      onSelected: (field) => onChanged(field, field == sort ? (order == 'asc' ? 'desc' : 'asc') : 'asc'),
      itemBuilder: (context) => [
        for (final field in fields.entries)
          PopupMenuItem(
            value: field.key,
            child: Row(children: [
              SizedBox(
                width: 32,
                child: field.key == sort ? Icon(order == 'asc' ? AppIcons.arrowUp : AppIcons.arrowDown, size: 18) : null,
              ),
              Text(field.value),
            ]),
          ),
      ],
    );
  }
}

/// An app-bar button that switches a list between rows and a grid of cards.
class ViewToggle extends StatelessWidget {
  const ViewToggle({super.key, required this.value, required this.onChanged});
  final ListLayout value;
  final ValueChanged<ListLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final grid = value == ListLayout.grid;
    return IconButton(
      tooltip: grid ? tr('Show as a list') : tr('Show as a grid'),
      onPressed: () => onChanged(grid ? ListLayout.list : ListLayout.grid),
      icon: Icon(grid ? AppIcons.listView : AppIcons.gridView),
    );
  }
}

/// A shimmer passing over placeholder shapes (SkeletonBox) while something
/// loads. Still when the device asks for less motion.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});
  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highlight = Colors.white.withAlpha(dark ? 26 : 150);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [Colors.transparent, highlight, Colors.transparent],
          stops: const [0.35, 0.5, 0.65],
          transform: _SlideGradient(_controller.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.progress);
  final double progress;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
}

/// One placeholder shape. A null height fills the space it is given.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.circle = false});
  final double? width;
  final double? height;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(appStyle == AppStyle.brutalism ? 0 : 6),
      ),
    );
  }
}

/// Placeholder rows shaped like ListTiles: a circle and two lines each.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 8, this.leading = true});
  final int count;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              if (leading) ...[const SkeletonBox(width: 40, height: 40, circle: true), const SizedBox(width: 16)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FractionallySizedBox(
                    widthFactor: 0.45 + (i * 3 % 5) / 10,
                    alignment: Alignment.centerLeft,
                    child: const SkeletonBox(height: 16),
                  ),
                  const SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: 0.3 + (i * 2 % 4) / 10,
                    alignment: Alignment.centerLeft,
                    child: const SkeletonBox(height: 12),
                  ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// A placeholder card for a grid: a picture, a title and a line.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Skeleton(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: SkeletonBox(height: null)),
        SizedBox(height: 12),
        SkeletonBox(height: 16),
        SizedBox(height: 8),
        FractionallySizedBox(widthFactor: 0.6, alignment: Alignment.centerLeft, child: SkeletonBox(height: 12)),
      ]),
    );
  }
}
