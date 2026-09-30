{{flutter_js}}
{{flutter_build_config}}

const loadingScreen = document.getElementById('loading-screen');
const loadingMessage = document.getElementById('loading-message');

function onScriptError(event) {
  const target = event.target;
  if (target && target.tagName === 'SCRIPT') showLoadingError();
}

function stopWatchingErrors() {
  window.removeEventListener('error', onScriptError, true);
}

function removeLoadingScreen() {
  stopWatchingErrors();
  if (loadingScreen) loadingScreen.remove();
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

window.addEventListener('error', onScriptError, true);

_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      window.addEventListener('flutter-first-frame', removeLoadingScreen, { once: true });
      await appRunner.runApp();
    } catch (error) {
      console.error(error);
      showLoadingError();
    }
  }
}).catch(showLoadingError);
