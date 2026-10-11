// Forms in steps. Owned by AppWand.
import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart' show ApiException, errorMessage;
import 'i18n.dart';
import 'icons.dart';
import 'theme.dart' show AppStyle, WizardIndicator, appStyle, wizardIndicator;
import 'widgets.dart' show AppSurface, showConfirmDialog, showSnack;

/// One step of a WizardForm.
class WizardStep {
  const WizardStep({
    required this.title,
    this.subtitle,
    this.icon,
    required this.builder,
    this.validate,
    this.fields = const [],
  });

  /// What the step is called, in the indicator and over its fields.
  final String title;

  /// A line under the title saying what the step asks for.
  final String? subtitle;

  /// Shown in the step's mark in place of its number.
  final IconData? icon;

  /// The step's fields. WizardForm puts them in a Form of the step's own, so
  /// their validators run when Next is pressed.
  final WidgetBuilder builder;

  /// A check of the whole step after its fields are valid (two fields that
  /// must agree, a look-up through the API): a message refuses Next and is
  /// shown, null or an empty text lets it through.
  final FutureOr<String?> Function()? validate;

  /// The JSON field names this step fills. When the API refuses the form with
  /// field errors, WizardForm opens the first step that names one of them.
  final List<String> fields;
}

/// A form in steps: the indicator, one step at a time, Back and Next, and one
/// submit at the end.
class WizardForm extends StatefulWidget {
  const WizardForm({
    super.key,
    required this.steps,
    required this.onSubmit,
    this.submitLabel,
    this.review,
    this.reviewTitle,
    this.reviewSubtitle,
    this.maxWidth = 720,
  });

  final List<WizardStep> steps;

  /// Sends the form, once every step is valid. What it throws is shown, and
  /// an ApiException's field errors open the step they belong to.
  final Future<void> Function() onSubmit;

  /// The last button's text; "Submit" when left out.
  final String? submitLabel;

  /// A last step showing what was entered before it is sent, usually a
  /// WizardSummary. Left out, the last of [steps] submits.
  final WidgetBuilder? review;
  final String? reviewTitle;
  final String? reviewSubtitle;

  final double maxWidth;

  /// The form around [context]: its step and goTo.
  static WizardFormState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WizardScope>()!.state;

  /// The API's error for [field] after a refused submit, or null. For a
  /// field's InputDecoration(errorText: ...).
  static String? errorOf(BuildContext context, String field) =>
      context.dependOnInheritedWidgetOfExactType<_WizardScope>()?.errors[field];

  @override
  State<WizardForm> createState() => WizardFormState();
}

class WizardFormState extends State<WizardForm> {
  final _scroll = ScrollController();
  List<GlobalKey<FormState>> _forms = [];

  /// The steps opened so far. They stay built, so their fields keep what was
  /// entered; a step not reached yet is not built.
  final _opened = <int>{0};
  int _index = 0;
  bool _dirty = false;
  bool _busy = false;
  Map<String, String> _errors = const {};

  bool get _hasReview => widget.review != null;
  int get _count => widget.steps.length + (_hasReview ? 1 : 0);
  bool get _onReview => _hasReview && _index == widget.steps.length;

  /// The step on screen, from 0. The review step is the one after the last.
  int get index => _index;

  @override
  void initState() {
    super.initState();
    _forms = [for (var i = 0; i < widget.steps.length; i++) GlobalKey<FormState>()];
  }

  @override
  void didUpdateWidget(WizardForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wanted = widget.steps.length;
    if (_forms.length == wanted) return;
    _forms = [for (var i = 0; i < wanted; i++) i < _forms.length ? _forms[i] : GlobalKey<FormState>()];
    _opened.removeWhere((step) => step >= _count);
    if (_index >= _count) _index = _count - 1;
    _opened.add(_index);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _show(int step) {
    setState(() {
      _index = step.clamp(0, _count - 1).toInt();
      _opened.add(_index);
      // Past the first step there is something to lose, whatever kind of field it was entered in.
      if (_index > 0) _dirty = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Opens a step already passed, or the next one once this one is valid.
  Future<void> goTo(int step) async {
    if (_busy) return;
    final target = step.clamp(0, _count - 1).toInt();
    while (_index < target) {
      if (!await _check() || !mounted) return;
      _show(_index + 1);
    }
    if (target < _index) _show(target);
  }

  void back() {
    if (!_busy && _index > 0) _show(_index - 1);
  }

  Future<void> next() async {
    if (_busy) return;
    if (!await _check()) return;
    if (!mounted) return;
    if (_index < _count - 1) {
      _show(_index + 1);
    } else {
      await _submit();
    }
  }

  /// Whether the step on screen may be left forwards.
  Future<bool> _check() async {
    if (_onReview) return true;
    FocusManager.instance.primaryFocus?.unfocus();
    final form = _forms[_index].currentState;
    if (form != null && !form.validate()) return false;
    final validate = widget.steps[_index].validate;
    if (validate == null) return true;
    setState(() => _busy = true);
    String? problem;
    try {
      problem = await validate();
    } catch (e) {
      problem = errorMessage(e);
    }
    if (!mounted) return false;
    setState(() => _busy = false);
    if (problem == null || problem.isEmpty) return true;
    showSnack(context, problem, error: true);
    return false;
  }

  Future<void> _submit() async {
    // A step changed after it was passed (through the indicator) is checked again.
    for (var i = 0; i < _forms.length; i++) {
      final form = _forms[i].currentState;
      if (form != null && !form.validate()) {
        _show(i);
        return;
      }
    }
    setState(() {
      _busy = true;
      _errors = const {};
    });
    try {
      await widget.onSubmit();
      _dirty = false;
    } catch (e) {
      if (!mounted) return;
      final errors = e is ApiException ? e.fieldErrors : const <String, String>{};
      final step = errors.isEmpty ? -1 : widget.steps.indexWhere((s) => s.fields.any(errors.containsKey));
      setState(() => _errors = errors);
      if (step >= 0) _show(step);
      showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Something was typed or picked in the step on screen.
  void _touched() {
    final fields = _onReview ? const <String>[] : widget.steps[_index].fields;
    final stale = fields.any(_errors.containsKey);
    if (_dirty && !stale) return;
    setState(() {
      _dirty = true;
      if (stale) _errors = {for (final e in _errors.entries) if (!fields.contains(e.key)) e.key: e.value};
    });
  }

  /// Back (the app bar's arrow, the device's button) steps back through the
  /// form, and asks before what was entered is lost.
  Future<void> _leave(bool didPop, Object? result) async {
    if (didPop || _busy) return;
    if (_index > 0) {
      back();
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: tr('Discard what you entered?'),
      message: tr('What you entered on this form will be lost.'),
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final steps = widget.steps;
    final title = _onReview ? (widget.reviewTitle ?? tr('Review')) : steps[_index].title;
    final subtitle = _onReview
        ? (widget.reviewSubtitle ?? tr('Check everything before you send it.'))
        : steps[_index].subtitle;
    final last = _index == _count - 1;

    Widget stepAt(int i) {
      final current = i == _index;
      final review = i == steps.length;
      return Offstage(
        key: ValueKey('wizard-step-$i'),
        offstage: !current,
        child: TickerMode(
          enabled: current,
          child: ExcludeFocus(
            excluding: !current,
            child: review
                ? Builder(builder: widget.review!)
                : Form(key: _forms[i], onChanged: _touched, child: Builder(builder: steps[i].builder)),
          ),
        ),
      );
    }

    return _WizardScope(
      state: this,
      index: _index,
      errors: _errors,
      child: PopScope<Object?>(
        canPop: _index == 0 && !_dirty,
        onPopInvokedWithResult: _leave,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 600;
          final content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Step {current} of {total}', {'current': _index + 1, 'total': _count}),
                style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
              ),
              const SizedBox(height: 4),
              Text(title, style: theme.textTheme.titleLarge),
              if (subtitle != null && subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              const SizedBox(height: 20),
              // The review step is built again each time it is opened, so it shows what is entered now.
              for (var i = 0; i < _count; i++)
                if (_opened.contains(i) && (i < steps.length || i == _index)) stepAt(i),
            ],
          );
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: _WizardIndicator(
                    titles: [for (final step in steps) step.title, if (_hasReview) widget.reviewTitle ?? tr('Review')],
                    icons: [for (final step in steps) step.icon, if (_hasReview) null],
                    index: _index,
                    wide: wide,
                    onTap: _busy ? null : goTo,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    child: wide ? AppSurface(padding: const EdgeInsets.all(24), child: content) : content,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(children: [
                    if (_index > 0) OutlinedButton(onPressed: _busy ? null : back, child: Text(tr('Back'))),
                    const Spacer(),
                    FilledButton(
                      onPressed: _busy ? null : next,
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(last ? (widget.submitLabel ?? tr('Submit')) : tr('Next')),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

class _WizardScope extends InheritedWidget {
  const _WizardScope({required this.state, required this.index, required this.errors, required super.child});

  final WizardFormState state;
  final int index;
  final Map<String, String> errors;

  @override
  bool updateShouldNotify(_WizardScope oldWidget) => index != oldWidget.index || errors != oldWidget.errors;
}

/// Where the form stands, drawn as the app's wizardIndicator says: numbered
/// steps, dots or a bar. The numbers carry the steps' titles on wide screens.
class _WizardIndicator extends StatelessWidget {
  const _WizardIndicator({
    required this.titles,
    required this.icons,
    required this.index,
    required this.wide,
    required this.onTap,
  });

  final List<String> titles;
  final List<IconData?> icons;
  final int index;
  final bool wide;

  /// Opens a step; only the ones already passed can be tapped.
  final void Function(int step)? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = titles.length;
    // Square marks where the style has square corners.
    final corner = appStyle == AppStyle.brutalism ? 0.0 : (appStyle == AppStyle.flat ? 4.0 : 999.0);
    final frame = appStyle == AppStyle.brutalism ? Border.all(color: scheme.onSurface, width: 2) : null;
    const moving = Duration(milliseconds: 200);

    switch (wizardIndicator) {
      case WizardIndicator.bar:
        return Semantics(
          label: tr('Step {current} of {total}', {'current': index + 1, 'total': count}),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: (index + 1) / count),
            duration: moving,
            builder: (context, value, child) => DecoratedBox(
              decoration: BoxDecoration(border: frame, borderRadius: BorderRadius.circular(corner)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(corner),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  color: scheme.primary,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
        );
      case WizardIndicator.dots:
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkResponse(
                onTap: i < index && onTap != null ? () => onTap!(i) : null,
                radius: 16,
                child: Tooltip(
                  message: titles[i],
                  child: AnimatedContainer(
                    duration: moving,
                    width: i == index ? 28 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: i <= index ? scheme.primary : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(corner),
                      border: frame,
                    ),
                  ),
                ),
              ),
            ),
        ]);
      case WizardIndicator.numbers:
        Widget line(bool shown, bool done) => Expanded(
              child: Container(
                height: 2,
                color: !shown ? Colors.transparent : (done ? scheme.primary : scheme.outlineVariant),
              ),
            );
        Widget mark(int i) {
          final done = i < index;
          final current = i == index;
          final fill = done || current ? scheme.primary : scheme.surfaceContainerHighest;
          final ink = done || current ? scheme.onPrimary : scheme.onSurfaceVariant;
          return AnimatedContainer(
            duration: moving,
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(corner), border: frame),
            child: done
                ? Icon(AppIcons.check, size: 18, color: ink)
                : (icons[i] != null
                    ? Icon(icons[i], size: 18, color: ink)
                    : Text('${i + 1}', style: theme.textTheme.labelLarge?.copyWith(color: ink))),
          );
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: InkWell(
                onTap: i < index && onTap != null ? () => onTap!(i) : null,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    Row(children: [
                      line(i > 0, i <= index),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: mark(i)),
                      line(i < count - 1, i < index),
                    ]),
                    if (wide)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                        child: Text(
                          titles[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: i == index ? scheme.onSurface : scheme.onSurfaceVariant,
                            fontWeight: i == index ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
        ]);
    }
  }
}

/// One group of a WizardSummary: a heading and what was entered under it.
class WizardSummarySection {
  const WizardSummarySection({required this.title, required this.rows, this.step});

  final String title;

  /// Label → value, in the order shown. An empty value shows as a dash.
  final Map<String, String> rows;

  /// The step (from 0) these values were entered in: adds an Edit button
  /// that opens it.
  final int? step;
}

/// What was entered, for a WizardForm's review step.
class WizardSummary extends StatelessWidget {
  const WizardSummary({super.key, required this.sections});

  final List<WizardSummarySection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const Divider(height: 32),
          Row(children: [
            Expanded(child: Text(sections[i].title, style: theme.textTheme.titleMedium)),
            if (sections[i].step != null)
              TextButton(
                onPressed: () => WizardForm.of(context).goTo(sections[i].step!),
                child: Text(tr('Edit')),
              ),
          ]),
          for (final row in sections[i].rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 2, child: Text(row.key, style: theme.textTheme.bodyMedium?.copyWith(color: muted))),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: Text(row.value.isEmpty ? '—' : row.value, style: theme.textTheme.bodyLarge)),
              ]),
            ),
        ],
      ],
    );
  }
}
