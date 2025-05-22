--------------------------------------------------------------------------------
-- generate_data.sql
-- Скрипт для генерации тестовых данных для оптимизации функции F_WORKS_LIST
-- Структура: TemplateType → PrintTemplate → Organization → Employee →
--             Analiz → Works → WorkItem
-- 
-- Требования к данным:
-- - Works: 50 000 записей
-- - WorkItem: 150 000 записей (≈3 на заказ)
-- - Employee, WorkStatus, Analiz: справочники
--------------------------------------------------------------------------------
SET NOCOUNT ON;
GO

--------------------------------------------------------------------------------
-- 1. TemplateType
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.TemplateType)
BEGIN
    INSERT INTO dbo.TemplateType (TemlateVal, [Comment])
    VALUES 
      ('Standard',   'Стандартный шаблон'),
      ('Detailed',   'Подробный шаблон'),
      ('Compact',    'Компактный шаблон'),
      ('Custom',     'Пользовательский шаблон');
END
GO

--------------------------------------------------------------------------------
-- 2. PrintTemplate
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.PrintTemplate)
BEGIN
    INSERT INTO dbo.PrintTemplate (TemplateName, Ext, [Comment], Id_TemplateType)
    SELECT 
      'Template_' + CAST(t.Id_TemplateType AS VARCHAR),
      CASE WHEN t.Id_TemplateType % 2 = 0 THEN '.docx' ELSE '.pdf' END,
      'Генерированный шаблон #' + CAST(t.Id_TemplateType AS VARCHAR),
      t.Id_TemplateType
    FROM dbo.TemplateType AS t;
END
GO

--------------------------------------------------------------------------------
-- 3. Organization
--------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.Organization)
BEGIN
    INSERT INTO dbo.Organization (ORG_NAME, TEMPLATE_FN, Id_PrintTemplate, Email, Fax)
    SELECT
      'Org_' + CAST(p.Id_PrintTemplate AS VARCHAR),
      'Template_' + CAST(p.Id_PrintTemplate AS VARCHAR),
      p.Id_PrintTemplate,
      'org' + CAST(p.Id_PrintTemplate AS VARCHAR) + '@example.com',
      '+7-495-000-' + RIGHT('000' + CAST(p.Id_PrintTemplate AS VARCHAR),4)
    FROM dbo.PrintTemplate AS p;
END
GO

--------------------------------------------------------------------------------
-- 4. Employee
--------------------------------------------------------------------------------
;WITH nums AS (
    SELECT TOP(100) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects
)
INSERT INTO dbo.Employee (Login_Name, [Name], Patronymic, Surname, Email, Post)
SELECT
  'user' + RIGHT('000' + CAST(n AS VARCHAR), 3),
  'Имя'   + CAST(n AS VARCHAR),
  'Отчество' + CAST(n AS VARCHAR),
  'Фамилия'  + CAST(n AS VARCHAR),
  'user' + CAST(n AS VARCHAR) + '@test.local',
  CASE WHEN n % 3 = 0 THEN 'LabTech' 
       WHEN n % 3 = 1 THEN 'Doctor' 
       ELSE 'Admin' END
FROM nums
WHERE NOT EXISTS(SELECT 1 FROM dbo.Employee);
GO

--------------------------------------------------------------------------------
-- 5. Analiz
--------------------------------------------------------------------------------
;WITH nums AS (
    SELECT TOP(200) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects
)
INSERT INTO dbo.Analiz (IS_GROUP, MATERIAL_TYPE, CODE_NAME, FULL_NAME, Text_Norm, Price)
SELECT
   CASE WHEN n % 10 = 0 THEN 1 ELSE 0 END,
   n % 5,
   'CODE_' + RIGHT('000' + CAST(n AS VARCHAR), 3),
   'Анализ ' + CAST(n AS VARCHAR),
   'Норма_' + CAST(n AS VARCHAR),
   CAST((10 + RAND(CAST(NEWID() AS VARBINARY)) * 90) AS DECIMAL(8,2))
FROM nums
WHERE NOT EXISTS(SELECT 1 FROM dbo.Analiz);
GO

--------------------------------------------------------------------------------
-- 6. Works
--------------------------------------------------------------------------------
;WITH nums AS (
    SELECT TOP(50000) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Works
    (IS_Complit, Id_Employee, ID_ORGANIZATION, Org_Name, FIO, MaterialNumber, StatusId)
SELECT
    0,
    ((n - 1) % (SELECT COUNT(*) FROM dbo.Employee)) + 1,
    ((n - 1) % (SELECT COUNT(*) FROM dbo.Organization)) + 1,
    o.ORG_NAME,
    'Пациент_' + CAST(n AS VARCHAR),
    CAST(n * (RAND(CAST(NEWID() AS VARBINARY)) + 1) AS DECIMAL(8,2)),
    ((n - 1) % (SELECT COUNT(*) FROM dbo.WorkStatus)) + 1
FROM nums AS x
CROSS APPLY (
    SELECT TOP 1 * 
    FROM dbo.Organization 
    WHERE ID_ORGANIZATION = ((x.n - 1) % (SELECT COUNT(*) FROM dbo.Organization)) + 1
) AS o
WHERE NOT EXISTS(SELECT 1 FROM dbo.Works);
GO

--------------------------------------------------------------------------------
-- 7. WorkItem
--------------------------------------------------------------------------------
;WITH nums AS (
    SELECT TOP(150000) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b CROSS JOIN sys.all_objects c
)
INSERT INTO dbo.WorkItem
    (Is_Complit, Id_Employee, ID_ANALIZ, Id_Work, Is_Print, Is_Select, Is_NormTextPrint, Price)
SELECT
    CASE WHEN n % 4 = 0 THEN 1 ELSE 0 END,
    ((n - 1) % (SELECT COUNT(*) FROM dbo.Employee)) + 1,
    ((n - 1) % (SELECT COUNT(*) FROM dbo.Analiz)) + 1,
    ((n - 1) % (SELECT COUNT(*) FROM dbo.Works)) + 1,
    1,  -- Is_Print
    CASE WHEN n % 5 = 0 THEN 1 ELSE 0 END,
    1,  -- Is_NormTextPrint
    CAST((5 + RAND(CAST(NEWID() AS VARBINARY)) * 20) AS DECIMAL(8,2))
FROM nums
WHERE NOT EXISTS(SELECT 1 FROM dbo.WorkItem);
GO

PRINT '=== Генерация тестовых данных завершена ===';
