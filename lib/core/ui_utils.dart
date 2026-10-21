import 'package:flutter/foundation.dart';

/// Disposes controllers created for a dialog after its exit animation has
/// finished. Disposing them as soon as `showDialog` returns can leave the
/// still-animating route's text field using a disposed controller, which leads
/// to "A TextEditingController was used after being disposed" and follow-up
/// framework assertions.
void disposeAfterDialog(Iterable<ChangeNotifier> notifiers) {
  Future<void>.delayed(const Duration(milliseconds: 500), () {
    for (final notifier in notifiers) {
      try {
        notifier.dispose();
      } catch (_) {
        // The controller may already have been disposed by its owner.
      }
    }
  });
}
