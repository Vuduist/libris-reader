# Libris Reader — спецификация для реализации

Flutter-приложение: клиент каталога Флибуста (OPDS) с читалкой EPUB/FB2. Переписывается с нуля по образцу старого приложения (см. скриншоты в ../_apk_screens/ если есть). Пакет: com.example.libris. Язык UI — русский (оставить вкладки «Discover» и «Library» на английском, как в оригинале).

## Зависимости (pubspec.yaml)

flutter_bloc, equatable, http, xml, html, epubx, archive, hive, hive_flutter, shared_preferences, path_provider, cached_network_image, url_launcher, share_plus, intl, collection.

## Источники данных (проверено, всё работает)

Образцы ответов лежат в ../_samples/ (search_books.xml, search_authors2.xml, new.xml, author.xml, author_alpha.xml, livelib_top.html).

### Flibusta OPDS, база: https://m.flibusta.is (хранить в настройках, поле «Адрес каталога», editable)

- Новые релизы: GET {base}/opds/new/0/new → Atom feed с `<entry>` книг.
- Поиск книг: GET {base}/opds/opensearch?searchType=books&searchTerm={urlEncoded} → feed книг.
- Поиск авторов: GET {base}/opds/search?searchType=authors&searchTerm={q} → feed NAV-элементов (entry без acquisition-ссылок), у каждого link href="/opds/author/{id}".
- Поиск серий: GET {base}/opds/search?searchType=sequences&searchTerm={q} → NAV-элементы, link href="/opds/sequencebooks/{id}".
- Страница автора: GET {base}/opds/author/{id} → 5 entries: «Об авторе» (с content-HTML биографией и image-портретом), «Книги по сериям» → /opds/authorsequences/{id}, «Книги вне серий» → /opds/author/{id}/authorsequenceless, «Книги по алфавиту» → /opds/author/{id}/alphabet, «Книги по дате поступления» → /opds/author/{id}/time. ВАЖНО: эти 4 ссылки надо просто брать из entry (generic-навигация по href), не конструировать вручную.
- Любой feed книг: пагинация через `<link rel="next" href="...">`.
- Каждая книга-entry: title, author/name + author/uri, category label (жанры), dc:language, dc:format, dc:issued, content type="text/html" (аннотация, HTML-escaped), cover: link rel="http://opds-spec.org/image" href="/i/.../cover.jpg", закачки: link rel="http://opds-spec.org/acquisition/open-access" type="application/epub+zip" href="/b/{id}/epub", type="application/fb2+zip" href="/b/{id}/fb2" и др. Относительные href дополнять базой.
- «Книги по сериям» (/opds/authorsequences/{id}) возвращает NAV-элементы серий, каждая → /opds/sequencebooks/{id} → feed книг серии.

### LiveLib (всероссийский рейтинг, замена «Бестселлеров» с Флибусты)

GET https://www.livelib.ru/books/top с User-Agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)". HTML-парсинг (пакет html):
- карточки: `<a class="book-item__title" href="/book/..." title="Автор - Название">Название</a>`
- рейтинг: `<div class="book-item__rating">4,8</div>`
- обложка: в соседнем `<img data-pagespeed-lazy-src="https://s1.livelib.ru/boocover/...">` (атрибут alt="Автор - Название")
- автор: из title-атрибута ссылки (часть до " - ") или `<a class="book-item__author">`.
Брать первые ~20. При любой ошибке парсинга — просто скрывать секцию, не падать. Тап по книге рейтинга → поиск книги на Флибусте по названию, открыть детали первого результата (с индикатором загрузки).

### Wikipedia/Wiktionary (словарь для окна «Поиск»)

1. https://ru.wikipedia.org/api/rest_v1/page/summary/{urlEncodedTerm} → JSON: title, extract, thumbnail.source, content_urls. Показывать как «Источник: Wikipedia (ru)».
2. Если 404 — https://ru.wiktionary.org/w/api.php?action=query&prop=extracts&explaintext=1&format=json&titles={term} → взять extract первой страницы.
3. Если ничего — экран «Ничего не найдено для "…"» + кнопка «Искать в Google» → url_launcher https://www.google.com/search?q={term}.

### Перевод выделенного текста

GET https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl={ru|en}&dt=t&q={text} → JSON-массив, склеить [0][i][0]. Направление: если в тексте есть кириллица → tl=en, иначе tl=ru. Показывать в bottom sheet.

## Хранение

- Hive (без codegen, обычные Map-записи или ручные адаптеры) — боксы: books, notes, bookmarks.
- shared_preferences — настройки: themeMode (system/light/dark/sepia), readingMode (paged/scroll) — НОВАЯ настройка, opdsBaseUrl, fontSize (double, default 18).
- Файлы: {appDocuments}/Libris/Books/{id}.{epub|fb2|zip}, обложки {appDocuments}/Libris/Covers/{id}.jpg — обложки ОБЯЗАТЕЛЬНО сохранять при добавлении книги (исправление бага: в старой версии обложки не сохранялись).

### Модель книги в библиотеке

id (flibusta id из /b/{id}/), title, authors (List<String>), format (epub/fb2/...), filePath, coverPath, coverUrl, addedAt, lastOpenedAt, pinned (bool), progressChapter (int), progressOffset (double — scroll offset для scroll-режима), progressPage (int — для paged-режима), progressIsCfi? не нужно.

## Экраны

### Главная оболочка

BottomNavigationBar: Discover (compass icon), Library (books icon), Настройки (gear). Активный таб — тёмно-синяя «пилюля» (#1B3A6B) как на скриншоте.

### Discover

- Заголовок «Discover», строка поиска с подсказкой «Search books, authors...», при вводе — кнопка очистки X.
- Без запроса: секция «Новые релизы» (горизонтальный скролл карточек: обложка, название, автор) и секция «Бестселлеры» (то же + бейдж рейтинга LiveLib).
- С запросом: сегмент-переключатель «Книги | Авторы | Серии» (выбранный — тёмно-синий фон, галочка). Результаты:
  - Книги: список карточек (обложка слева, название жирным, автор, аннотация 2 строки). Тап → страница книги.
  - Авторы: простые строки «Фамилия Имя / Автор» со стрелкой. Тап → страница автора. ИСПРАВЛЕНИЕ БАГА: книги автора должны открываться (generic OPDS-навигация, см. выше).
  - Серии: строки с названием серии. Тап → список книг серии (/opds/sequencebooks/{id}).
- Пагинация результатов поиска книг через rel=next (догрузка при скролле или кнопка «Ещё»).

### Страница автора

AppBar «Книги автора {Имя}». Карточка «Об авторе»: портрет + биография (strip HTML, многоточие + раскрытие по тапу — опционально). Ниже 4 строки-раздела («Книги по сериям», «Книги вне серий», «Книги по алфавиту», «Книги по дате поступления») с placeholder-обложкой — тап → generic OPDS list page (загружает href, показывает книги или под-разделы рекурсивно: NAV-элементы — строками, книги — карточками, пагинация rel=next).

### Страница книги (Book detail)

Обложка, название, авторы (тап → страница автора), жанры-чипы, год, язык, аннотация (strip HTML). Кнопки скачивания по доступным форматам (предпочтение EPUB, затем FB2): «Скачать EPUB», «Скачать FB2». Прогресс скачивания. После скачивания: кнопка «Читать», книга в библиотеке. Если уже в библиотеке — «Читать» и «Удалить».

### Library

AppBar «Мои книги» + иконка поиска (раскрывающееся поле фильтра по названию/автору). Сетка 2 колонки: обложка (файл coverPath, иначе cached_network_image по coverUrl, иначе placeholder-иконка книги), название (жирным, 2 строки), автор (1 строка), тег формата (EPUB / EPUB+ZIP / FB2 ...) + дата добавления. Сортировка: сначала закреплённые, затем по lastOpenedAt/addedAt desc. Долгое нажатие → bottom sheet: «Закрепить»/«Открепить» (pinned=true поднимает вверх), «Удалить» (с подтверждением, удалять файл и обложку). Тап → читалка. PDF и прочие неподдерживаемые форматы: snackbar «Формат не поддерживается» (не падать).

### Настройки

- Раздел «Оформление»: радио Системная / Светлая / Темная / Сепия (Охра).
- Раздел «Режим чтения» (НОВОЕ): радио «По страницам (горизонтально)» / «Скролл (вертикально)».
- Раздел «Каталог»: текстовое поле адреса OPDS (default https://m.flibusta.is), кнопка «Сбросить».
- «О приложении»: Libris Reader Beta, версия 1.0.0.

### Читалка

Парсинг книг — свои сервисы:
- EPUB: пакет epubx. Получить список глав (spine/reading order), у каждой — title (из TOC navMap, сопоставление по href) и HTML-контент. Собрать карту сносок: во всех XHTML-документах элементы с id, на которые ссылаются `<a epub:type="noteref">` или href с '#'; целевой элемент с epub:type="note"/"footnote"/"rearnote" или просто элемент с данным id.
- FB2 (и fb2 в zip через archive): пакет xml. body → section (title → heading, p → абзацы, epigraph, poem/stanza/v, empty-line → отступ). Сноски: body name="notes", section id="..."; ссылки `<a type="note" l:href="#id">`.
- HTML→блоки: свой парсер на пакете html. Типы блоков: heading1-3, paragraph, epigraph (italic, indent), image. Inline: b/strong, i/em, sup, a (href). Результат: List<ReaderBlock> с List<ReaderSpan>{text, bold, italic, sup, linkHref}. img → bytes из epub-архива (epubx Content) или fb2 binary; отображать Image.memory с ограничением высоты.

UI читалки:
- AppBar: слева иконка «три линии» → Drawer с содержанием (список глав, текущая выделена жирным, тап → переход). Центр: стрелки ‹ › (предыдущая/следующая глава) + название текущей главы. Справа ⋮ меню: «Закладки», «Увеличить текст» (A+), «Уменьшить текст» (A−), «Закрыть книгу».
- Тело — два режима (из настроек):
  - Скролл (вертикально): SingleChildScrollView с блоками текущей главы. Позиция = chapterIndex + scrollController.offset.
  - По страницам (горизонтально): пагинация блоков главы через TextPainter (размер шрифта из настроек, ширина/высота viewport минус паддинги): жадно набирать блоки на страницу; абзац длиннее страницы — делить бинарным поиском по символам. PageView. Позиция = chapterIndex + pageIndex. Внизу индикатор «стр. N из M».
- Выделение текста: SelectableText.rich на каждом текстовом блоке, contextMenuBuilder → своя панель (AdaptiveTextSelectionToolbar.buttonItems) с кнопками: «Заметка», «Поиск», «Копировать», «Перевести».
  - «Заметка» → bottom sheet со списком заметок книги + поле ввода, предзаполненное выделенным текстом (сохранение в Hive).
  - «Поиск» → bottom sheet словаря (Wikipedia/Wiktionary, см. выше).
  - «Копировать» → Clipboard.
  - «Перевести» → bottom sheet с переводом.
- Сноски: тап по inline-ссылке: если href резолвится в текст сноски (карта сносок) → bottom sheet с содержимым сноски (заголовок «Сноска»); если внутренняя ссылка на главу → переход; внешняя → url_launcher.
- «Закладки» в ⋮ меню → bottom sheet: кнопка «Добавить закладку» (текущая позиция + первые ~80 символов текста), список закладок (тап → переход, свайп/иконка — удаление).
- Сохранение позиции: Timer.periodic(10 сек) + WidgetsBindingObserver (paused/inactive/detached) + dispose. При открытии книги — восстановить позицию (глава + offset/page).
- Размер шрифта A+/A−: шаг 2, диапазон 12–32, persist в shared_preferences; при смене режима/шрифта позиция пересчитывается хотя бы по главе.
- Тема читалки = тема приложения (сепия-фон и т.д.).

## Темы оформления

- Сепия (Охра): фон #F1E7D0, карточки/панели #EAE0C8, текст #3B2F1F, акцент #1B3A6B.
- Светлая: белый фон, тот же акцент. Тёмная: стандартная dark, акцент светлее (#7FA6E8).
- Шрифт системный. Скругления карточек 12–16.

## Состояние

flutter_bloc: SearchBloc (query+tab+pagination), DiscoverCubit (новинки + бестселлеры), AuthorCubit, BookDetailCubit (детали + скачивание + статус в библиотеке), LibraryCubit, SettingsCubit, ReaderCubit (книга, главы, позиция, режим, шрифт), NotesCubit/BookmarksCubit (можно частью ReaderCubit).

## Приёмка

1. `flutter analyze` — без ошибок.
2. `flutter build apk --release` — успешно, APK в build/app/outputs/flutter-apk/app-release.apk.
3. Код компилируется под Android SDK 36, minSdk 21+.
