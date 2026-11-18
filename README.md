# Модификация Yandex Music (macOS, Electron)

Версия приложения, под которую сделаны правки: **5.127.0**.
Приложение — Electron, интерфейс лежит в `Contents/Resources/app.asar` (Next.js, статический экспорт).

Что сделано:
1. Убрана тяжёлая шейдерная анимация Vibe (грузила видеоядро).
2. Экран «Моя волна» заменён на экран очереди из полноэкранного плеера («Сейчас играет / Далее в очереди»), встроенный в страницу, боковое меню остаётся.
3. Убраны пункты меню «Концерты» и «Книги и подкасты» вместе с их экранами.
4. Градиент от чёрного меню к контенту, обложка и очередь на `grid`, кнопки списка/текстов на обложке скрыты.
5. Отключена проверка обновлений.

## Какие файлы менять

Все пути внутри `app.asar`. Копии изменённых файлов лежат в `patched/` с теми же путями.

| Файл в asar | Что изменено |
|---|---|
| `app/_next/static/chunks/7404.ef5161e1786d9a67.js` | `"undefined"==typeof Worker` → `!0`: форсирует запасной вариант без шейдера |
| `app/_next/static/chunks/2179.aa6f48bcd35fa0fd.js` | то же самое |
| `app/_next/static/chunks/6200-46a206102fea5578.js` | список пунктов меню: `!1&&` перед добавлением `eH.CONCERTS`; `WebNextDisableNonMusic`-проверка заменена на `!0\|\|c.push({id:eH.NON_MUSIC…` |
| `app/_next/static/chunks/app/(product)/(app)/concerts/page-5e386cffa9a15f4e.js` | экспорт `default` заменён на `()=>null` |
| `app/_next/static/chunks/app/(product)/(app)/non-music/page-7cc1d9bf027641c3.js` | экспорт `NonMusicPage` заменён на `()=>null` |
| `app/_next/static/chunks/2009-dc28e54eb8251823.js` | вместо экрана «Моя волна» (`rn`) рендерится `_QW`, который берёт `window.__YMQ` (запасной вариант — старый `rn`) |
| `app/_next/static/chunks/9427.1ff43f90f4440df7.js` | модуль 76348: новый компонент `_YQ` (экран очереди + CSS + градиент), экспортируется как `window.__YMQ` |
| `index.js` (корень asar) | `check()` и `start()` класса апдейтера сразу `return` — проверка обновлений отключена |

Ищите в каждом файле собственные вставки по маркерам: `__YMQ`, `_YQ`, `_QW`, `data-ymq`, `!1&&`, `!0||c.push`, `return;` в `check()`/`start()`.

**Важно:** имена чанков содержат хэш и меняются с каждой версией приложения. Файлы из `patched/` подходят только к версии 5.127.0. Для другой версии правки нужно накатывать заново по таблице выше (найти те же места по коду).

## Как собрать и установить

Патченую копию нельзя ставить в `/Applications`: macOS (App Management) блокирует запись. Копия живёт в `~/Applications/Yandex Music.app`.

```bash
# 0. Один раз: бэкапы и копия приложения
mkdir -p backup
cp "/Applications/Yandex Music.app/Contents/Resources/app.asar" backup/app.asar.orig
cp "/Applications/Yandex Music.app/Contents/Info.plist" backup/Info.plist.orig
cp -R "/Applications/Yandex Music.app" ~/Applications/

# 1. Распаковать
cd tools && npm install && cd ..
npx --prefix tools @electron/asar extract backup/app.asar.orig work/

# 2. Положить изменённые файлы поверх (или патчить вручную)
cp -R patched/* work/

# 3. Запаковать (node_modules остаются распакованными)
npx --prefix tools @electron/asar pack work new.asar --unpack-dir "{node_modules/**}"

# 4. Подменить asar и обновить контрольную сумму в Info.plist
DST="$HOME/Applications/Yandex Music.app"
OLD=$(node tools/asar-hash.mjs "$DST/Contents/Resources/app.asar")
NEW=$(node tools/asar-hash.mjs new.asar)
pkill -f "Applications/Yandex Music.app"
cp new.asar "$DST/Contents/Resources/app.asar"
sed -i '' "s/$OLD/$NEW/" "$DST/Contents/Info.plist"
codesign --force --deep -s - "$DST"

# 5. Запуск (не через open: bundle id совпадает с оригиналом)
nohup "$DST/Contents/MacOS/"* >/dev/null 2>&1 &
```

Контрольная сумма `ElectronAsarIntegrity` в `Info.plist` — это SHA256 заголовка asar (считает `tools/asar-hash.mjs`). Если её не обновить, приложение падает с ошибкой `Integrity check failed for asar archive`.

## Подводные камни

- **Автообновление оригинала.** Оригинал в `/Applications` обновляется сам и перепишет свой asar. Копия в `~/Applications` не затрагивается, в ней проверка обновлений отключена.
- **Подпись.** Копия подписана ad-hoc (`codesign -s -`), это нормально для локального запуска.
- **Сброс плеера.** Компонент очереди при уходе с экрана вызывает `reset()` общего хранилища полноэкранного плеера; настоящий полноэкранный плеер после этого может открыться в состоянии по умолчанию.
- **Проверка без записи экрана.** Права на запись экрана нет, поэтому скриншоты снимались отладочной сборкой: в `index.js` добавлялся хук с `webContents.capturePage()`. В итоговой сборке этого хука нет.
- **Раскладка.** Экран очереди рисуется родным компонентом плеера (`s1`), а `grid`, градиент и скрытие кнопок — это CSS в строке `<style>` внутри `_YQ` (атрибут `data-ymq`). Чтобы вернуть родное поведение «обложка по центру → уезжает влево» с анимацией, нужно убрать этот CSS и заменить `vw/vh` на `cqw/cqh` в четырёх правилах и четырёх `@keyframes` модуля `FullscreenPlayerDesktopContent`.
