# PROJECT_STATUS — Shikimori iOS

Обновлено: 23.11.2026. Этап 2 (Подготовка): ЗАВЕРШЁН. Этап 3 (Проектирование): начат.

## Принятые решения
1. Технология: нативный SwiftUI. Liquid Glass через `.glassEffect`, нужен Xcode 26.
2. Сборка: GitHub Actions, `macos-26`, публичный репозиторий (бесплатно без лимита минут).
3. Результат сборки: неподписанный IPA, подпись на iPhone (Mango или LCSign).
4. Данные: напрямую с shikimori.io (GraphQL для чтения, REST v1/v2 для остального), без своего сервера.
5. OAuth2: пользователь регистрирует своё приложение на shikimori.io/oauth/applications; client_id/secret вводятся в приложении, хранятся в Keychain.
6. Бюджет: 0 ₽.

## Данные пользователя
- GitHub: Oxyr1ze, репозиторий публичный: Oxyr1ze/shikimori-ios
- Подпись: Mango или LCSign на iPhone 17 (iOS 27.2.1)
- Bundle ID из профиля: app.panda1248.maroon8441 (прописан в project.yml)

## OAuth-приложение (24.11.2026)
- Создано на shikimori.io как «ShikiApp», redirect `urn:ietf:wg:oauth:2.0:oob` (вход через код на экране).
- Доступны только scope: user_rates, comments, topics. Остальные (email, messages, content, clubs, friends, ignores) на сайте отключены, включаются администрацией Shikimori по запросу.
- Следствие (до проверки): личные сообщения, добавление/удаление друзей, вступление в клубы и игнор через приложение, вероятно, недоступны. Чтение публичных данных проверяем.
- Client ID не секрет; Client Secret в репозиторий не попадает, хранится в Keychain на iPhone.

## Проверено реальными запросами с iPhone (24.11.2026)
- GraphQL POST /api/graphql (поиск аниме): работает без входа, HTTP 200.
- REST без входа: /api/animes, /api/animes/{id}, /api/animes/{id}/similar, /api/topics?forum=news: HTTP 200.
- Картинки приходят относительными путями (/system/animes/original/...): дописывать https://shikimori.io.
- /api/calendar: один раз TLS-ошибка сети, повторить.
- Вход OAuth: страница кода выдала «Client authentication failed due to unknown client». Причина не установлена, вероятно, неверно введён Client ID (похожие символы I/l, 0/O). Проверяем.

## Статус функций
Тестовый экран (градиент + стеклянная карточка): РЕАЛИЗОВАНО, сборка в GitHub Actions прошла успешно (23.11.2026). ПРОВЕРЕНО НА iPhone (23.11.2026): подписан в Mango/LCSign, установился и запустился, Liquid Glass отображается.
Экран «Проверка API» (сборка 0.0.2): написан, сборка не проверена, на iPhone не проверен.
Остальные функции: запланировано.

## Не проверено
- Сборка на `macos-26` (arm64) не стартовала: у GitHub не было свободных серверов. Используем `macos-26-intel` — работает.
- Страницы /api/doc, лимиты запросов, redirect-схема OAuth.

## Следующий шаг
Зарегистрировать своё OAuth-приложение на Shikimori, проверить API реальными запросами, затем дизайн-концепция.
