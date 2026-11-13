import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'format.dart';

/// Shown instead of a rupee amount while amounts are hidden.
const hiddenAmountText = '₹ ••••';

/// Screen-reader text for a hidden amount (so the bullets are not read out digit by digit).
const hiddenAmountSemantics = 'amount hidden';

/// A rupee amount, or the mask when [hide] is true.
String amountText(int paise, {required bool hide}) => hide ? hiddenAmountText : formatInr(paise);

/// Dashboard privacy switch for rupee amounts.
///
/// Hidden at every app launch and deliberately NOT saved: a "visible" choice that survived a restart
/// would put takings on the landing page for anyone who glances at the phone.
class HideAmountsNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final hideAmountsProvider = NotifierProvider<HideAmountsNotifier, bool>(HideAmountsNotifier.new);
