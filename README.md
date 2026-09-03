# repo_bundles_cli — выгрузка репозиториев в bundle

Утилита для выгрузки git- и mercurial-репозиториев в файлы bundle. Bundle — самодостаточный
архив, в который попадает вся история, все ветки, все теги, а для git — ещё и рефы
ревью: `refs/merge-requests/*` (GitLab) и `refs/pull/*` (GitHub). На каждый репозиторий
получается один файл, который удобно передавать.

## Использование

1. Сделайте скрипт исполняемым:

   ```bash
   chmod +x make_bundles.sh
   ```

2. Создайте файл `repos.txt` — по одному URL репозитория на строку. Пустые строки
   и строки, начинающиеся с `#`, игнорируются:

   ```
   https://gitlab.com/your-org/backend.git
   https://gitlab.com/your-org/mobile-app.git
   git@github.com:your-org/web.git
   https://foss.heptapod.net/your-group/legacy
   hg+https://hg.example.org/old-project
   ```

   Поддерживаются https- и ssh-ссылки. Нужен доступ к репозиториям: при
   необходимости скрипт запросит логин/пароль или использует ваш ssh-ключ.

3. Запустите:

   ```bash
   ./make_bundles.sh repos.txt ./bundles
   ```

   Готовые файлы появятся в каталоге `./bundles` с именами по namespace
   репозитория:

   ```
   bundles/your-org__backend.bundle
   bundles/your-org__mobile-app.bundle
   bundles/your-group__legacy.hgbundle
   ```

## Git и Mercurial

Система контроля версий определяется автоматически по ссылке, как в `repo_metadata_cli`:

- префикс схемы `hg+<url>` или `git+<url>` — явное указание, приоритетнее автоопределения;
- суффикс `.git` — git;
- известные hg-хосты (`hg.mozilla.org`, `*.heptapod.net`, `mercurial-scm.org` и т.п.) — mercurial;
- всё остальное (GitHub, GitLab и пр.) — git.

Git-бандлы сохраняются как `*.bundle`, mercurial-бандлы — как `*.hgbundle`.

Для mercurial нужна команда `hg`:

```bash
pip install mercurial
```

Без `hg` mercurial-репозитории пропускаются с ошибкой, git-репозитории выгружаются как обычно.

## Что делает скрипт

Для каждого URL:

- git: `git clone --mirror` → дотягивает рефы ревью → `git bundle create --all` →
  `git bundle verify`;
- mercurial: `hg clone -U` → `hg bundle --all` → `hg debugbundle`;
- удаляет временный клон.

### Рефы ревью

`git clone --mirror` забирает только то, что сервер анонсирует: ветки, теги, notes.
Ветки merge request'ов и pull request'ов туда не попадают — GitLab и GitHub держат их
в скрытых пространствах имён. А это значит, что коммиты незамерженных или удалённых
после мержа веток в bundle не попадут: история будет короче, чем в исходном
репозитории.

Поэтому после клонирования скрипт отдельно дотягивает их явными refspec'ами:

```
+refs/merge-requests/*:refs/merge-requests/*   # GitLab
+refs/pull/*:refs/pull/*                       # GitHub
```

Нет такого пространства имён — не ошибка, репозиторий выгружается как обычно. Сколько
рефов ревью попало в bundle, видно в строке результата: `OK (12M, рефов ревью: 37)`.

Выключить (например, если MR-рефов тысячи и bundle раздувается):

```bash
HIDDEN_REFS=0 ./make_bundles.sh repos.txt
```

Оговорка на будущее: клон из готового bundle подтягивает только `refs/heads` и теги,
поэтому `git rev-list --all` в таком клоне рефы ревью не увидит — до них нужно
дотягиваться из bundle тем же явным refspec'ом.

В конце печатает сводку и завершается с ненулевым кодом, если хотя бы один
репозиторий не удалось выгрузить.

## Аргументы

```
./make_bundles.sh <файл-со-списком-url> [каталог-вывода]
```

- `<файл-со-списком-url>` — обязательный; по одному URL на строку.
- `[каталог-вывода]` — необязательный, по умолчанию `./bundles`.
