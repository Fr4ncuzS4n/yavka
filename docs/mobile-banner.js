/* Предложение веб-версии на телефоне: на iOS ставить APK-подобное
   приложение без подписи Apple нельзя, поэтому сайт предлагает открыть
   «Явку» в браузере и добавить на домашний экран (PWA). */
(function () {
  'use strict';

  // Уже внутри веб-версии — ничего не предлагаем.
  if (location.pathname.indexOf('/app/') !== -1) return;

  var ua = navigator.userAgent || '';
  var isIOS = /iPad|iPhone|iPod/.test(ua) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var isAndroidPhone = /Android/.test(ua) && /Mobile Safari/.test(ua);
  if (!isIOS && !isAndroidPhone) return;

  // Приложение уже стоит как PWA — баннер не нужен.
  if (window.matchMedia('(display-mode: standalone)').matches ||
      navigator.standalone) return;

  function buildBanner() {
    var banner = document.createElement('div');
    banner.className = 'mobile-banner';
    banner.setAttribute('role', 'region');
    banner.setAttribute('aria-label', 'Веб-версия «Явки»');

    var text = document.createElement('p');
    if (isIOS) {
      text.innerHTML = 'Вы на iPhone? Устанавливать приложение не нужно: ' +
        '<a href="/yavka/app/">откройте «Явку» в браузере</a> и добавьте ' +
        'на домашний экран — «Поделиться» → «На экран „Домой“».';
    } else {
      text.innerHTML = 'Вы на телефоне? Можно поставить приложение ' +
        '(<a href="https://github.com/Fr4ncuzS4n/yavka/releases/latest">APK</a>) ' +
        'или <a href="/yavka/app/">открыть веб-версию</a> — без установки.';
    }
    banner.appendChild(text);

    var close = document.createElement('button');
    close.className = 'mobile-banner-close';
    close.type = 'button';
    close.setAttribute('aria-label', 'Скрыть');
    close.textContent = '×';
    close.addEventListener('click', function () {
      banner.remove();
      try { localStorage.setItem('yavka-web-banner', 'hidden'); } catch (e) { /* приватный режим */ }
    });
    banner.appendChild(close);

    try {
      if (localStorage.getItem('yavka-web-banner') === 'hidden') return;
    } catch (e) { /* приватный режим — показываем */ }

    document.body.appendChild(banner);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', buildBanner);
  } else {
    buildBanner();
  }
})();
