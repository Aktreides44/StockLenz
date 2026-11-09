// The watchlist: companies the user wants to follow, saved on this device (see device_settings.dart).
// The screener, the phone cards and the company page all show the same list, so it lives in one
// shared object. It is a ChangeNotifier: whenever a ticker is added or removed it "notifies its
// listeners", and every screen that listens redraws its stars.
import 'package:flutter/material.dart';

import 'device_settings.dart';

class Watchlist extends ChangeNotifier {
  Set<String> _tickers = {};

  int get length => _tickers.length;

  bool contains(String ticker) => _tickers.contains(ticker);

  /// Read the saved list (called once when the screener opens).
  Future<void> load() async {
    _tickers = await loadWatchlist();
    notifyListeners();
  }

  /// Add the ticker if it isn't on the list, otherwise remove it; then save.
  void toggle(String ticker) {
    _tickers = contains(ticker) ? ({..._tickers}..remove(ticker)) : ({..._tickers}..add(ticker));
    notifyListeners();
    saveWatchlist(_tickers);
  }
}

/// The one watchlist the whole app uses.
final watchlist = Watchlist();

/// A ☆ button: filled when the company is on the watchlist. Tapping it adds or removes the company.
class WatchStar extends StatelessWidget {
  const WatchStar({super.key, required this.ticker, this.small = false});

  final String ticker;

  /// Smaller version for the table rows.
  final bool small;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: watchlist,
      builder: (context, _) {
        final watched = watchlist.contains(ticker);
        return IconButton(
          onPressed: () => watchlist.toggle(ticker),
          icon: Icon(watched ? Icons.star : Icons.star_border),
          color: watched ? Theme.of(context).colorScheme.primary : null,
          tooltip: watched ? 'Remove $ticker from watchlist' : 'Add $ticker to watchlist',
          iconSize: small ? 18 : null,
          visualDensity: VisualDensity.compact,
          padding: small ? EdgeInsets.zero : null,
          constraints: small ? const BoxConstraints.tightFor(width: 24, height: 24) : null,
        );
      },
    );
  }
}
