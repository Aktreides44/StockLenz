// App settings that differ between "real use" and development.

/// Where the StockLens API runs. By default the hosted server on Render.
///
/// To use the API on your own PC instead, start the app with:
///   flutter run -d windows --dart-define=API_URL=http://127.0.0.1:8000
const String apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://stocklens-api-43hi.onrender.com',
);

/// How long to wait for an answer. Render's free tier sleeps after ~15 minutes without
/// visitors and needs 30–60 seconds to wake up, so this is generous.
/// (If there is no connection at all, the request fails right away, not after this time.)
const Duration apiTimeout = Duration(seconds: 60);
