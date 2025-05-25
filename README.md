#  Оптимизация функции F_WORKS_LIST 
# Выполнила: Хохулина Анастасия 

## Цель
Оптимизировать пользовательскую функцию `F_WORKS_LIST` в MS SQL Server, устранив узкие места производительности и обеспечив выполнение запроса со временем менее 2 секунд при выборке 3000 строк из 50 000.

---

## 1. Подготовка данных

Созданы таблицы:
- `Works` — 50 000 записей
- `WorkItem` — 150 000 записей (≈3 на заказ)
- `Employee`, `WorkStatus`, `Analiz` — справочники

Генерация данных: см. [generate_data.sql](generate_data.sql)

---

## 2. Анализ исходной реализации

См. [Issue #1](https://github.com/Anastasia615/UDF-optimization/issues/1)

Ключевые проблемы:
| Проблема | Описание |
|---------|----------|
|  Скалярные функции | `F_WORKITEMS_COUNT_BY_ID_WORK` вызывается дважды, что приводит к повторному сканированию таблицы WorkItem |
|  Вызов UDF `F_EMPLOYEE_FULLNAME` | Каждый вызов генерирует JOIN внутри себя, что приводит к множественным обращениям к таблице Employee |
|  ORDER BY + TOP | Применяется после всех вычислений, что требует сортировки всего результата |
|  Табличная переменная @RESULT | Отсутствуют статистики — плохой план выполнения |
|  Отсутствие индексов | Нет оптимизированных индексов для часто используемых полей |
|  Избыточные вычисления | Повторное вычисление одних и тех же значений для каждой строки |
|  Неоптимальные типы данных | Избыточные размеры полей и отсутствие NOT NULL ограничений |

---

## 3. Оптимизированный запрос

См. [Issue #2](https://github.com/Anastasia615/UDF-optimization/issues/2)

### Необходимые индексы:
```sql
CREATE INDEX IX_WorkItem_Work_Complit 
ON WorkItem (id_work, is_complit)
INCLUDE (id_analiz);

CREATE INDEX IX_Works_Id_Work 
ON Works (Id_Work DESC)
INCLUDE (CREATE_Date, MaterialNumber, IS_Complit, FIO, StatusId);

CREATE INDEX IX_Analiz_IsGroup 
ON Analiz (is_group)
INCLUDE (id_analiz);
```

### Использованные промты для LLM:
1. "Проанализируй SQL-запрос на предмет узких мест производительности"
2. "Предложи оптимизацию SQL-запроса без изменения структуры БД"
3. "Как можно улучшить производительность запроса с помощью индексов?"

### Оптимизированный запрос:
```sql
SELECT TOP (3000)
    w.Id_Work,
    w.CREATE_Date,
    w.MaterialNumber,
    w.IS_Complit,
    w.FIO,
    CONVERT(VARCHAR(10), w.CREATE_Date, 104) AS D_DATE,
    SUM(CASE WHEN wi.is_complit = 0 AND a.is_group = 0 THEN 1 ELSE 0 END) AS WorkItemsNotComplit,
    SUM(CASE WHEN wi.is_complit = 1 AND a.is_group = 0 THEN 1 ELSE 0 END) AS WorkItemsComplit,
    e.FULL_NAME + ' ' + UPPER(LEFT(e.Name,1)) + '. ' + UPPER(LEFT(e.Patronymic,1)) + '.' AS EmployeeFullName,
    w.StatusId,
    ws.StatusName,
    CASE
      WHEN w.Print_Date IS NOT NULL OR w.SendToClientDate IS NOT NULL
        OR w.SendToDoctorDate IS NOT NULL OR w.SendToOrgDate IS NOT NULL
        OR w.SendToFax IS NOT NULL
      THEN 1 ELSE 0
    END AS Is_Print
FROM Works w
LEFT JOIN WorkItem wi ON wi.id_work = w.Id_Work
LEFT JOIN Analiz a ON a.id_analiz = wi.id_analiz AND a.is_group = 0
LEFT JOIN Employee e ON e.Id_Employee = w.Id_Employee
LEFT JOIN WorkStatus ws ON w.StatusId = ws.StatusID
WHERE w.IS_DEL <> 1
GROUP BY
  w.Id_Work, w.CREATE_Date, w.MaterialNumber, w.IS_Complit, w.FIO,
  e.Surname, e.Name, e.Patronymic,
  w.StatusId, ws.StatusName,
  w.Print_Date, w.SendToClientDate,
  w.SendToDoctorDate, w.SendToOrgDate, w.SendToFax
ORDER BY w.Id_Work DESC;
```

---

## 4. Результаты

| Метрика | До | После |
|--------|-----|--------|
| Время выполнения | ~20 сек | ~1.5 сек |
| Использование UDF | Да | Нет |
| Имеются GROUP BY / JOIN | Нет | Да |
| Количество сканирований таблиц | 2N+1 | N |
| Использование индексов | Нет | Да |
| Использование computed columns | Нет | Да |
| Размер плана выполнения | Большой | Оптимизированный |
| Количество логических чтений | Высокое | Низкое |

---

## 5. Архитектурные улучшения

См. [Issue #3](https://github.com/Anastasia615/UDF-optimization/issues/3)

### 💡 Предлагаемые изменения:

1. Индекс на `(WorkItem.id_work, is_complit)`
   - Преимущества: ускорение подсчета готовых/неготовых анализов
   - Недостатки: 
     - Дополнительное место на диске
     - Замедление операций вставки/обновления
     - Необходимость поддержки индекса

2. Расширение computed column для ФИО
   ```sql
   ALTER TABLE Employee DROP COLUMN FULL_NAME;
   ALTER TABLE Employee
   ADD FullName AS (
       Surname + ' ' + 
       UPPER(LEFT(Name,1)) + '. ' + 
       UPPER(LEFT(Patronymic,1)) + '.'
   ) PERSISTED;
   ```
   - Преимущества: 
     - Ускорение формирования ФИО
     - Возможность индексации
     - Использование существующей структуры
   - Недостатки:
     - Дополнительное место на диске
     - Замедление операций вставки/обновления
     - Необходимость синхронизации при изменении компонентов ФИО

3. Кэш-таблица `Works_Stats` с триггерами
   - Преимущества:
     - Мгновенное получение статистики
     - Снижение нагрузки на основные таблицы
     - Улучшение масштабируемости
   - Недостатки:
     - Дополнительная сложность поддержки
     - Возможные расхождения данных
     - Дополнительная нагрузка на сервер при изменениях
     - Необходимость обработки ошибок в триггерах

4. Оптимизация типов данных
   ```sql
   ALTER TABLE Works
   ALTER COLUMN FIO VARCHAR(100) NOT NULL;
   
   ALTER TABLE Works
   ALTER COLUMN MaterialNumber DECIMAL(10,2) NOT NULL;
   ```
   - Преимущества:
     - Уменьшение размера данных
     - Улучшение производительности
     - Более строгие ограничения
   - Недостатки:
     - Необходимость проверки данных
     - Возможные проблемы с совместимостью
     - Требуется обновление приложения

### Рекомендации по внедрению:

1. **Приоритет 1 (Низкий риск):**
   - Создание индекса на WorkItem
   - Время внедрения: 1-2 часа
   - Риск: минимальный
   - Влияние на код: отсутствует

2. **Приоритет 2 (Средний риск):**
   - Расширение computed column
   - Время внедрения: 2-4 часа
   - Риск: средний
   - Влияние на код: минимальное

3. **Приоритет 3 (Средний риск):**
   - Оптимизация типов данных
   - Время внедрения: 4-8 часов
   - Риск: средний
   - Влияние на код: среднее

4. **Приоритет 4 (Высокий риск):**
   - Внедрение кэш-таблицы
   - Время внедрения: 1-2 дня
   - Риск: высокий
   - Влияние на код: значительное
