{{flutter_js}}
{{flutter_build_config}}

const loadingScreen = document.getElementById('loading-screen');
const loadingMessage = document.getElementById('loading-message');

function stopWatchingErrors() {
  window.removeEventListener('error', showLoadingError, true);
  window.removeEventListener('unhandledrejection', showLoadingError);
}

function showLoadingError() {
  if (!loadingScreen || !loadingScreen.isConnected) return;

  stopWatchingErrors();
  loadingMessage.textContent = 'The demo could not be loaded. ';
  const link = document.createElement('a');
  link.href = 'https://pub.dev/packages/find_in_page';
  link.textContent = 'View find_in_page on pub.dev.';
  loadingMessage.appendChild(link);
  const indicator = document.getElementById('loading-indicator');
  if (indicator) indicator.remove();
}

window.addEventListener('error', showLoadingError, true);
window.addEventListener('unhandledrejection', showLoadingError);

try {
  _flutter.loader.load({
    onEntrypointLoaded: async function(engineInitializer) {
      try {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
        stopWatchingErrors();
        if (loadingScreen) loadingScreen.remove();
      } catch (error) {
        showLoadingError();
      }
    }
  });
} catch (error) {
  showLoadingError();
}
