import 'package:democracy/src/design/components/native_controls.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tabs that can lend the tab bar's round accessory an action.
enum TabSlot { tracker, community }

/// What the accessory beside the iOS tab bar does while a tab is showing.
///
/// Elsewhere it is the 개표 destination. On a tab that has one primary
/// action -- report a pledge, write a review -- it becomes that action, so
/// the page does not float a second button of its own.
@immutable
class TabAccessory {
  const TabAccessory({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final AppIcon icon;
  final VoidCallback onPressed;
}

final tabAccessoriesProvider =
    NotifierProvider<TabAccessories, Map<TabSlot, TabAccessory>>(
      TabAccessories.new,
    );

class TabAccessories extends Notifier<Map<TabSlot, TabAccessory>> {
  @override
  Map<TabSlot, TabAccessory> build() => const {};

  void set(TabSlot slot, TabAccessory? accessory) {
    final next = {...state};
    if (accessory == null) {
      next.remove(slot);
    } else {
      next[slot] = accessory;
    }
    state = next;
  }
}

/// Lends [accessory] to the tab bar while this widget is in the tree.
///
/// A null [accessory] withdraws it -- the community tab offers one only on
/// its reviews pane.
class TabAccessoryScope extends ConsumerStatefulWidget {
  const TabAccessoryScope({
    required this.slot,
    required this.accessory,
    required this.child,
    super.key,
  });

  final TabSlot slot;
  final TabAccessory? accessory;
  final Widget child;

  @override
  ConsumerState<TabAccessoryScope> createState() => _TabAccessoryScopeState();
}

class _TabAccessoryScopeState extends ConsumerState<TabAccessoryScope> {
  late final TabAccessories _registry = ref.read(
    tabAccessoriesProvider.notifier,
  );

  void _publish() {
    // After the frame: a provider must not change while widgets build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _registry.set(widget.slot, widget.accessory);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _publish();
  }

  @override
  void didUpdateWidget(TabAccessoryScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    // By label: the callback is a fresh closure on every build, and
    // republishing on each would rebuild the shell for nothing.
    if (oldWidget.accessory?.label != widget.accessory?.label) {
      _publish();
    }
  }

  @override
  void dispose() {
    final registry = _registry;
    final slot = widget.slot;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => registry.set(slot, null),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
