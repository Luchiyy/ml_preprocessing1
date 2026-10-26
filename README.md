# ml_preprocessing 

Расширение PostgreSQL на языке C для предобработки данных непосредственно в SQL:

- `handle_missing_values` — заполнение пропусков;
- `standardize_matrix` — стандартизация матриц;
- `one_hot_encode_column` — кодирование категориальных признаков.

Инструкция рассчитана на PostgreSQL 18 x64. Установка и SQL-проверки выполнены на Ubuntu и Windows.

## 1. Что потребуется пользователю

Если получена **готовая библиотека для вашей ОС, архитектуры и основной версии PostgreSQL**, собирать расширение самостоятельно не требуется. Для установки нужны три файла:

| Ubuntu | Windows | Назначение |
| --- | --- | --- |
| `ml_preprocessing.so` | `ml_preprocessing.dll` | Скомпилированный модуль |
| `ml_preprocessing.control` | `ml_preprocessing.control` | Параметры расширения |
| `ml_preprocessing--1.0.sql` | `ml_preprocessing--1.0.sql` | Регистрация SQL-функций |

Для запуска проверок понадобится также папка `sql`. Если получены только исходники, сначала выполните сборку по инструкции для своей ОС. Готовую Linux-библиотеку нужно собирать для совместимого окружения: совпадения архитектуры и версии PostgreSQL недостаточно для гарантии совместимости системных библиотек.

Расширение устанавливают один раз в каталоги выбранной установки PostgreSQL, а затем подключают отдельно в каждой нужной базе. Сборка при каждом запросе или запуске PostgreSQL не требуется.

## 2. Ubuntu

### 2.1. Установка PostgreSQL

В обычном терминале:

```bash
sudo apt update
sudo apt install postgresql-18 postgresql-client-18
```

Проверка:

```bash
psql --version
pg_lsclusters
sudo -u postgres psql -d postgres -c "SELECT version();"
```

У кластера `18 main` ожидается статус `online`. Если он существует, но остановлен:

```bash
sudo pg_ctlcluster 18 main start
```


### 2.2. Сборка из исходников

Если уже есть подходящий готовый `.so`, переходите к пункту 2.3.

Установите компилятор, Make и серверные заголовки:

```bash
sudo apt install build-essential postgresql-server-dev-18
```

Распакуйте проект и перейдите в папку, содержащую `Makefile` и C-файлы. Пример, если папка называется `ml_preprocessing`:

```bash
cd ~/Downloads/ml_preprocessing
/usr/lib/postgresql/18/bin/pg_config --version
/usr/lib/postgresql/18/bin/pg_config --includedir-server
make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config
```

Путь в `cd` замените своим. При успешной сборке файл `ml_preprocessing.so` появится **в этой же папке рядом с Makefile**.

Установите расширение:

```bash
sudo make install PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config
```

`make install` копирует библиотеку, `.control` и SQL-файл в каталоги PostgreSQL. После этого переходите к пункту 2.4.

### 2.3. Установка готовой библиотеки

Выполняйте из папки с тремя файлами расширения. Здесь предполагаются стандартные каталоги пакетов PostgreSQL 18 в Ubuntu:

```bash
sudo install -m 755 ml_preprocessing.so /usr/lib/postgresql/18/lib/
sudo install -m 644 ml_preprocessing.control ml_preprocessing--1.0.sql /usr/share/postgresql/18/extension/
```

При нестандартной установке проверьте пути через `pg_config --pkglibdir` и `pg_config --sharedir`: `.control` и SQL-файл помещаются в подкаталог `extension` общего каталога.

### 2.4. Подключение и проверка

Создайте новую тестовую базу, если её ещё нет:

```bash
sudo -u postgres createdb ml_preprocessing_test
```

Подключите расширение:

```bash
sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d ml_preprocessing_test -c "CREATE EXTENSION ml_preprocessing;"
```

Из папки проекта запустите все проверки:

```bash
sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d ml_preprocessing_test < sql/all_checks.sql
```

Ожидаемое последнее сообщение: `All preprocessing checks passed.`

Для интерактивной работы:

```bash
sudo -u postgres psql -d ml_preprocessing_test
```

Команда выхода из `psql`: `\q`.

## 3. Windows

### 3.1. Установка PostgreSQL

1. Откройте https://www.postgresql.org/download/windows/ и перейдите к установщику EDB.
2. Установите PostgreSQL 18 x64. Выберите PostgreSQL Server и Command Line Tools; pgAdmin можно установить для работы через графический интерфейс. Stack Builder для нашего расширения не требуется.
3. Запомните каталог установки, пароль пользователя `postgres` и порт сервера. В примерах используются `C:\Program Files\PostgreSQL\18` и порт `5432`.
4. Дождитесь завершения установки и запуска службы PostgreSQL.

В обычной командной строке **cmd.exe** проверьте:

```bat
"C:\Program Files\PostgreSQL\18\bin\psql.exe" --version
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d postgres -c "SELECT version();"
```

Введите пароль, заданный при установке. При другом каталоге или порте замените их во всех командах ниже.

### 3.2. Сборка из исходников

Если уже получена готовая DLL, переходите к пункту 3.3.

Установите Visual Studio или Build Tools for Visual Studio с компонентами **«Разработка классических приложений на C++»**, компилятором MSVC и Windows SDK. 

Откройте **x64 Native Tools Command Prompt for VS**. Следующие команды предназначены для этой командной строки.
Проверьте целевую архитектуру:

```bat
echo %VSCMD_ARG_TGT_ARCH%
```

Ожидается `x64`. Если показано `x86`, откройте именно консоль для x64.

Перейдите в распакованную папку проекта и задайте путь к PostgreSQL:

```bat
cd /d C:\Projects\ml_preprocessing
set "PGROOT=C:\Program Files\PostgreSQL\18"
dir "%PGROOT%\include\server\postgres.h"
dir "%PGROOT%\lib\postgres.lib"
```

Замените `C:\Projects\ml_preprocessing` своим путём. Если заголовков или `postgres.lib` нет, установите комплект разработки для той же версии PostgreSQL.

Соберите модуль одной командой:

```bat
cl /nologo /MD /LD /TC /std:c11 /utf-8 /DWIN32 /D_CRT_SECURE_NO_WARNINGS ^
 /I"%PGROOT%\include\server\port\win32_msvc" ^
 /I"%PGROOT%\include\server\port\win32" ^
 /I"%PGROOT%\include\server" /I"%PGROOT%\include" ^
 ml_preprocessing.c missing_values_pg.c standardize_pg.c standardize_core.c one_hot_pg.c one_hot_core.c ^
 /link /LIBPATH:"%PGROOT%\lib" postgres.lib /OUT:ml_preprocessing.dll /MACHINE:X64
```

Символ `^` должен быть последним символом строки, без пробелов после него.

При успешной сборке `ml_preprocessing.dll` появится **в текущей папке проекта**. Файлы `.obj`, `.exp` и создаваемая импортная `.lib` — промежуточные или вспомогательные; пользователю расширения передавать их не требуется.

Проверка архитектуры DLL:

```bat
dumpbin /headers ml_preprocessing.dll | findstr /i machine
```

В выводе ожидается `8664 machine (x64)`.

### 3.3. Установка DLL и служебных файлов

Откройте **cmd.exe от имени администратора**, перейдите в папку с файлами и выполните:

```bat
set "PGROOT=C:\Program Files\PostgreSQL\18"
copy /Y ml_preprocessing.dll "%PGROOT%\lib\"
copy /Y ml_preprocessing.control "%PGROOT%\share\extension\"
copy /Y ml_preprocessing--1.0.sql "%PGROOT%\share\extension\"
```

Для новой установки перезапуск сервера обычно не нужен. Если заменяете DLL, уже загруженную сервером, Windows может блокировать файл: закройте клиентские подключения и перезапустите службу PostgreSQL через `services.msc` после замены. При блокировке остановите службу перед копированием, затем запустите её снова; это прервёт работу всех баз этой службы.

### 3.4. Подключение и проверка

В **cmd.exe** задайте путь:

```bat
set "PGROOT=C:\Program Files\PostgreSQL\18"
```

Создайте тестовую базу, если её ещё нет:

```bat
"%PGROOT%\bin\createdb.exe" -h localhost -p 5432 -U postgres ml_preprocessing_test
```

Подключите расширение:

```bat
"%PGROOT%\bin\psql.exe" -X -v ON_ERROR_STOP=1 -h localhost -p 5432 -U postgres -d ml_preprocessing_test -c "CREATE EXTENSION ml_preprocessing;"
```

Из папки проекта запустите проверки:

```bat
"%PGROOT%\bin\psql.exe" -X -v ON_ERROR_STOP=1 -h localhost -p 5432 -U postgres -d ml_preprocessing_test -f "sql\all_checks.sql"
```

Ожидаемое последнее сообщение: `All preprocessing checks passed.`

Для интерактивной работы:

```bat
"%PGROOT%\bin\psql.exe" -h localhost -p 5432 -U postgres -d ml_preprocessing_test
```

## 4. Использование в любой ОС

В `psql` или Query Tool программы pgAdmin выполните:

```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname = 'ml_preprocessing';

SELECT ml_preprocessing_ping();
```

Ожидается версия расширения `1.0` и строка `C extension works`.

Примеры функций:

```sql
SELECT handle_missing_values(
    ARRAY[[1.0,NULL],[NULL,4.0],[3.0,6.0],[5.0,NULL]]::float8[],
    'mean'
);

SELECT * FROM standardize_matrix(
    ARRAY[[1.0,10.0],[2.0,20.0],[3.0,30.0],[NULL,40.0]]::float8[]
);

SELECT * FROM one_hot_encode_column(
    ARRAY['red','blue','red',NULL]::text[], 'color'
);
```

Функции возвращают результаты, не изменяя исходные таблицы. Пропуски обозначаются SQL `NULL`. Для обработки пропусков доступны `zeros`, `mean` и `median`. Стандартизация использует популяционное стандартное отклонение. One-hot возвращает матрицу `k × n`: строки — категории, столбцы — наблюдения.

Для подключения в другой базе откройте соединение с ней и выполните `CREATE EXTENSION ml_preprocessing;` от имени суперпользователя PostgreSQL. Повторять эту команду в уже подключённой базе не нужно. Установка расширения требует повышенных прав, обычные запросы после предоставления нужных прав может выполнять другой пользователь базы.