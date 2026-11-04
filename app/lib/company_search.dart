// The search in the top bar: type a ticker or a name, tap a suggestion, go straight to that company.
// (The search field above the list is different: it only filters the list.)
import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

/// The best matches for [query], best first:
///   1. the ticker is exactly the query ("KO" → Coca-Cola, not Kenvue)
///   2. the ticker starts with the query ("AM" → AMZN, AMD)
///   3. the name contains the query ("apple" → Apple Inc.)
/// Upper/lower case does not matter. An empty query gives no matches.
List<Company> findCompanies(List<Company> companies, String query, {int limit = 8}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [];

  int rank(Company company) {
    final ticker = company.ticker.toLowerCase();
    if (ticker == q) return 0;
    if (ticker.startsWith(q)) return 1;
    if (company.name.toLowerCase().contains(q)) return 2;
    return -1; // no match
  }

  final matches = companies.where((c) => rank(c) >= 0).toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.ticker.compareTo(b.ticker);
    });
  return matches.take(limit).toList();
}

/// A 🔍 button for the top bar. On phones the search opens full screen, on wide screens as a panel.
class CompanySearchButton extends StatelessWidget {
  const CompanySearchButton({super.key, required this.companies, required this.onSelected});

  final List<Company> companies;
  final void Function(Company company) onSelected;

  @override
  Widget build(BuildContext context) {
    return SearchAnchor(
      isFullScreen: isPhone(context),
      viewHintText: 'Go to company: ticker or name',
      builder: (context, controller) => IconButton(
        onPressed: controller.openView,
        icon: const Icon(Icons.search),
        tooltip: 'Find a company',
      ),
      suggestionsBuilder: (context, controller) {
        final query = controller.text;
        final matches = findCompanies(companies, query);
        if (query.trim().isNotEmpty && matches.isEmpty) {
          return [const ListTile(title: Text('No company matches.'))];
        }
        return [
          for (final company in matches)
            ListTile(
              leading: SizedBox(
                width: 64,
                child: Text(
                  company.ticker,
                  style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                ),
              ),
              title: Text(company.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(company.sector, style: const TextStyle(fontSize: FontSizes.small)),
              onTap: () {
                controller.closeView(''); // close the search and empty it for next time
                onSelected(company);
              },
            ),
        ];
      },
    );
  }
}
