{{flutter_js}}
{{flutter_build_config}}

async function startSpliTrip() {
  if ('serviceWorker' in navigator) {
    try {
      await navigator.serviceWorker.register(new URL('splitrip_service_worker.js', document.baseURI), {
        updateViaCache: 'none',
      });
      // Capture Firebase's dynamically imported SDK as well as Flutter's files
      // on the first visit, so the next cold start can work offline.
      if (!navigator.serviceWorker.controller) {
        await Promise.race([
          new Promise(resolve => navigator.serviceWorker.addEventListener('controllerchange', resolve, { once: true })),
          new Promise(resolve => setTimeout(resolve, 15000)),
        ]);
      }
    } catch (error) {
      console.warn('Offline installation unavailable; starting online.', error);
    }
  }
  // CanvasKit comes from gstatic.com/flutter-canvaskit/<engine revision>/:
  // immutable URLs, so the worker can cache whichever variant this browser uses.
  await _flutter.loader.load();
}

startSpliTrip();
