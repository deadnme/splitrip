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
  await _flutter.loader.load({
    config: { canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href },
  });
}

startSpliTrip();
