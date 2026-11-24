# ARCHITECTURE — как устроено приложение

Обновлено: 24.11.2026, сборка 0.1.14.

## Технологии
- Swift и SwiftUI, iOS 26, Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)`).
- XcodeGen: файл `project.yml` описывает проект, Xcode-проект создаётся на сборке.
- Сборка: GitHub Actions (`.github/workflows/build-ipa.yml`), раннер `macos-26-intel`, результат: неподписанный IPA как артефакт «Shikimori-unsigned-ipa».
- Данные: напрямую с shikimori.io, своего сервера нет.

## Структура папки `Shikimori/`
- `ShikimoriApp.swift`: точка входа, вкладки (Главная, Каталог, Списки, Профиль, Поиск).
- `Keychain.swift`: хранение client_id, client_secret и токенов в Keychain iPhone.
- `ApiChecker.swift`, `ApiCheckView.swift`: диагностика API.
- `Core/AuthManager.swift`: вход, токены, все запросы к API (REST v1/v2, GraphQL), ограничитель частоты (около 5 запросов в секунду), повтор при 401 и 429.
- `Core/Models.swift`: модели данных (тайтлы, списки, персонажи, комментарии, статистика).
- `Core/CommentParser.swift`: разбор HTML комментариев и описаний в блоки (текст, цитата, картинка, спойлер, смайлики).
- `Core/Components.swift`: общие элементы (постер, карточка, ряд, ошибка).
- `Core/Theme.swift`: цвета (системный фон, красный акцент).
- `Features/`: экраны (Home, Catalog, Search, Title, Lists, Profile, Calendar, Comments, Character, Stats, Setup).

## Ключевые решения
- Постеры: из REST приходят адреса, дающие у новых релизов заглушку, поэтому настоящие адреса запрашиваются через GraphQL, с запасными вариантами.
- Ссылки на страницы внутри уже открытых экранов делаются через `NavigationLink { ... } label: { ... }`, а не «по значению», иначе страница открывается повторно.
- Если запрос дополнительного блока (персонажи, похожее, друзья) не удался, блок молча не показывается, экран работает дальше.
- Структуру ответов API проверяем по открытому исходному коду Shikimori (github.com/shikimori/shikimori: `app/controllers/api`, `app/serializers`), так как страница документации из рабочей среды недоступна.

## Безопасность
- Client Secret, токены и пароли в репозиторий не попадают, хранятся только в Keychain на iPhone.
- Репозиторий публичный, секретов в нём нет.
