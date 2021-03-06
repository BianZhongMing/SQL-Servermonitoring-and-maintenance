--【数据库概况】
--1.数据库版本信息（含位数），实例名
select @@version VersionInfo,@@servicename InstanceName;

--2.数据库启动时间
select login_time,datediff(month,login_time,getdate()) 和当前日期的时间差
from master..sysprocesses where spid=1;

--3.数据库名称及数据量大小
--所有数据库空间占用
exec sp_helpdb;
--所有数据库的日志空间占用
dbcc sqlperf(logspace);
----------切入DB的查询
--占用空间中可使用的空间，index占用空间等明细
use datayesdb
GO
exec sp_spaceused ;
--数据文件物理信息明细
--way1:不用切DB，KB为单位
exec sp_helpdb 'datayesdb';
--sp_helpdb数据文件部分SQL提取（GB/MB）,需切DB
select   name
         , fileid
         , filename
         , filegroup = filegroup_name(groupid)
         , 'size' = convert(nvarchar(MAX), convert(bigint, size) * 8/1024./1024.) + N' GB'
         , 'maxsize' = (case maxsize when -1 then N'Unlimited' else convert(nvarchar(MAX), convert(bigint, maxsize) * 8/1024./1024.) + N' GB' end)
         , 'growth' = (case status & 0x100000 when 0x100000 then convert(nvarchar(MAX), growth) + N'%' else convert(nvarchar(15), convert(bigint, growth) * 8/1024.) + N' MB' end)
         , 'usage' = (case status & 0x40 when 0x40 then 'log only' else 'data only' end)
from     sysfiles
order by fileid
/*--way 2 查询文件组和文件
SELECT df.[name],
       df.physical_name,
       df.[size] * 8 [size],   --单位 page 1page=8k
       df.growth * 8 growth,
       f.[name] [filegroup],
       f.is_default,
       state,
       state_desc,
       max_size,
       create_lsn,
       drop_lsn,
       read_only_lsn,
       read_write_lsn,
       differential_base_lsn,
       differential_base_time
  FROM sys.database_files df
       JOIN sys.filegroups f ON df.data_space_id = f.data_space_id;
*/

--4.磁盘写入错误数
--磁盘读写情况
select 
@@total_read [读取磁盘次数],
@@total_write [写入磁盘次数],
@@total_errors [磁盘写入错误数],
getdate() [当前时间];

--5.CPU活动及工作情况
select
@@timeticks [每个时钟周期对应的微秒数],
@@cpu_busy*cast(@@timeticks as float)/1000 [CPU工作时间(秒)],
@@idle*cast(@@timeticks as float)/1000 [CPU空闲时间(秒)],
@@cpu_busy*cast(@@timeticks as float)/10
   /(@@cpu_busy*cast(@@timeticks as float)/1000+abs(@@idle*cast(@@timeticks as float)/1000)) [CPU工作时间比例(%)],
getdate() [当前时间];


--6.锁和等待
--检查等待类型中等待时间最长的10个类型
SELECT TOP ( 10 )
        wait_type ,
        waiting_tasks_count ,
        ( wait_time_ms - signal_wait_time_ms ) AS resource_wait_time ,
        max_wait_time_ms ,
        CASE waiting_tasks_count
          WHEN 0 THEN 0
          ELSE wait_time_ms / waiting_tasks_count
        END AS avg_wait_time
FROM    sys.dm_os_wait_stats
WHERE   wait_type NOT LIKE '%SLEEP%'   -- 去除不相关的等待类型
        AND wait_type NOT LIKE 'XE%'
        AND wait_type NOT IN -- 去除系统类型   
( 'KSOURCE_WAKEUP', 'BROKER_TASK_STOP', 'FT_IFTS_SCHEDULER_IDLE_WAIT',
  'SQLTRACE_BUFFER_FLUSH', 'CLR_AUTO_EVENT', 'BROKER_EVENTHANDLER',
  'BAD_PAGE_PROCESS', 'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE',
  'DBMIRROR_EVENTS_QUEUE', 'SQLTRACE_BUFFER_FLUSH', 'CLR_MANUAL_EVENT',
  'ONDEMAND_TASK_QUEUE', 'REQUEST_FOR_DEADLOCK_SEARCH', 'LOGMGR_QUEUE',
  'BROKER_RECEIVE_WAITFOR', 'PREEMPTIVE_OS_GETPROCADDRESS',
  'PREEMPTIVE_OS_AUTHENTICATIONOPS', 'BROKER_TO_FLUSH' )
ORDER BY wait_time_ms DESC ;



--7.表信息核查（大对象管控及处理）
--查看数据库中所有表的条数
SELECT SCHEMA_NAME(b.uid) AS SchemaName,
       b.name AS TableName,
       a.rowcnt AS CountNumber,
       a.dpages*8/1024. "DataUsed(MB)",
       a.reserved*8/1024. "DataReserved(MB)",
       a.used*8/1024.-a.dpages*8/1024. "IndexUsed(MB)",
       b.crdate as TableCreateDate,
       (select max(modify_date) from sys.tables s where s.name=b.name) as TableMaxAlterDate
  FROM sysindexes a, sysobjects b
 WHERE     a.id = b.id
       AND a.indid < 2
       AND objectproperty (b.id, 'IsMSShipped') = 0
       --AND b.name='md_security'
ORDER BY CountNumber DESC;

--内存占用
--查看SQL Server的实际内存占用
select * from sysperfinfo where counter_name like '%Memory%';
--查看每个数据库缓存大小
SELECT  COUNT(*) * 8 / 1024 AS 'Cached Size (MB)' ,
        CASE database_id
          WHEN 32767 THEN 'ResourceDb'
          ELSE DB_NAME(database_id)
        END AS 'Database'
FROM    sys.dm_os_buffer_descriptors
GROUP BY DB_NAME(database_id) ,
        database_id
ORDER BY 'Cached Size (MB)' DESC;
--查看虚拟内存保留情况
SELECT  [type] ,
        memory_node_id ,
       --page_size_bytes,--2012之前字段
       --pages_kb ,--2012字段
        virtual_memory_reserved_kb ,
        virtual_memory_committed_kb ,
        awe_allocated_kb
FROM    sys.dm_os_memory_clerks
ORDER BY virtual_memory_reserved_kb DESC;


--tempdb

--大查询
--查找CPU最高消耗的10个语句
SELECT TOP ( 10 )
        SUBSTRING(ST.text, ( QS.statement_start_offset / 2 ) + 1,
                  ( ( CASE statement_end_offset
                        WHEN -1 THEN DATALENGTH(st.text)
                        ELSE QS.statement_end_offset
                      END - QS.statement_start_offset ) / 2 ) + 1) AS statement_text ,
        execution_count ,
        total_worker_time / 1000 AS total_worker_time_ms ,
        ( total_worker_time / 1000 ) / execution_count AS avg_worker_time_ms ,
        total_logical_reads ,
        total_logical_reads / execution_count AS avg_logical_reads ,
        total_elapsed_time / 1000 AS total_elapsed_time_ms ,
        ( total_elapsed_time / 1000 ) / execution_count AS avg_elapsed_time_ms ,
        qp.query_plan
FROM    sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
ORDER BY total_worker_time DESC;


--得到最耗时的前10条T-SQL语句
;with maco as   
(     
    select top 10  
        plan_handle,  
        sum(total_worker_time) as total_worker_time ,  
        sum(execution_count) as execution_count ,  
        count(1) as sql_count  
    from sys.dm_exec_query_stats group by plan_handle  
    order by sum(total_worker_time) desc  
)  
select  t.text ,  
        a.total_worker_time ,  
        a.execution_count ,  
        a.sql_count  
from    maco a  
        cross apply sys.dm_exec_sql_text(plan_handle) t; 

--堆表筛查
;WITH tbinfo
         AS (SELECT TableName, isnull(PK_COUNT, 0) PK_COUNT, isnull(UN_C_COUNT, 0) UN_C_COUNT, isnull(IDX_COUNT, 0) IDX_COUNT
             FROM   (SELECT name TableName, id
                     FROM   sysobjects
                     WHERE  type <> 's' --S = 系统表
                                       AND xtype = 'U' /*U = 用户表*/
                                                      --and status>0 --查所有用户表
                    ) c
                    LEFT JOIN (SELECT   b.id
                                        , i.object_id
                                        , SUM(cast(i.is_primary_key AS INT)) AS PK_COUNT
                                        , --主键字段数,
                                         sum(cast(i.is_unique_constraint AS INT)) AS UN_C_COUNT
                                        , --唯一约束字段数
                                         sum(CASE WHEN i.is_primary_key = 1 OR i.is_unique_constraint = 1 THEN 0 ELSE 1 END) AS IDX_COUNT --索引包含字段数
                               FROM     sysindexes a
                                        JOIN sysindexkeys b ON a.id = b.id AND a.indid = b.indid
                                        JOIN syscolumns d ON b.id = d.id AND b.colid = d.colid
                                        JOIN sys.indexes i ON i.index_id = a.indid
                               WHERE    a.indid NOT IN (0, 255) --indid = 0 或 255则为表，其他为索引。
                                                               AND b.keyno <> 0
                               GROUP BY b.id, i.object_id) t
                      ON (t.id = c.id AND c.id = t.object_id))
  SELECT *
  FROM   tbinfo
  WHERE  PK_COUNT = 0 OR (UN_C_COUNT = 0 AND IDX_COUNT = 0);

--无用索引
SELECT  OBJECT_NAME(i.object_id) AS table_name ,
        COALESCE(i.name, SPACE(0)) AS index_name ,
        ps.partition_number ,
        ps.row_count ,
        CAST(( ps.reserved_page_count * 8 ) / 1024. AS DECIMAL(12, 2)) AS size_in_mb ,
        COALESCE(ius.user_seeks, 0) AS user_seeks ,
        COALESCE(ius.user_scans, 0) AS user_scans ,
        COALESCE(ius.user_lookups, 0) AS user_lookups ,
        i.type_desc
FROM    sys.all_objects t
        INNER JOIN sys.indexes i ON t.object_id = i.object_id
        INNER JOIN sys.dm_db_partition_stats ps ON i.object_id = ps.object_id
                                                   AND i.index_id = ps.index_id
        LEFT OUTER JOIN sys.dm_db_index_usage_stats ius ON ius.database_id = DB_ID()
                                                           AND i.object_id = ius.object_id
                                                           AND i.index_id = ius.index_id
WHERE   i.type_desc NOT IN ( 'HEAP', 'CLUSTERED' )
        AND i.is_unique = 0
        AND i.is_primary_key = 0
        AND i.is_unique_constraint = 0
        AND COALESCE(ius.user_seeks, 0) <= 0
        AND COALESCE(ius.user_scans, 0) <= 0
        AND COALESCE(ius.user_lookups, 0) <= 0
ORDER BY OBJECT_NAME(i.object_id) , i.name

--找出最高使用率的20%个查询
SELECT TOP 20 PERCENT
        cp.usecounts AS '使用次数' ,
        cp.cacheobjtype AS '缓存类型' ,
        cp.objtype AS [对象类型] ,
        st.text AS 'TSQL' ,
	--cp.plan_handle AS '执行计划',
        qp.query_plan AS '执行计划' ,
        cp.size_in_bytes AS '执行计划占用空间(Byte)'
FROM    sys.dm_exec_cached_plans cp
        CROSS APPLY sys.dm_exec_sql_text(plan_handle) st
        CROSS APPLY sys.dm_exec_query_plan(plan_handle) qp
ORDER BY usecounts DESC;

-- 未被使用的索引
SELECT  OBJECT_NAME(i.[object_id]) AS [Table Name] ,
        i.name
FROM    sys.indexes AS i
        INNER JOIN sys.objects AS o ON i.[object_id] = o.[object_id]
WHERE   i.index_id NOT IN ( SELECT  ddius.index_id
                            FROM    sys.dm_db_index_usage_stats AS ddius
                            WHERE   ddius.[object_id] = i.[object_id]
                                    AND i.index_id = ddius.index_id
                                    AND database_id = DB_ID() )
        AND o.[type] = 'U'
ORDER BY OBJECT_NAME(i.[object_id]) ASC;

--需要维护但是未被用过的索引
SELECT  '[' + DB_NAME() + '].[' + su.[name] + '].[' + o.[name] + ']' AS [statement] ,
        i.[name] AS [index_name] ,
        ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] AS [user_reads] ,
        ddius.[user_updates] AS [user_writes] ,
        SUM(SP.rows) AS [total_rows]
FROM    sys.dm_db_index_usage_stats ddius
        INNER JOIN sys.indexes i ON ddius.[object_id] = i.[object_id]
                                    AND i.[index_id] = ddius.[index_id]
        INNER JOIN sys.partitions SP ON ddius.[object_id] = SP.[object_id]
                                        AND SP.[index_id] = ddius.[index_id]
        INNER JOIN sys.objects o ON ddius.[object_id] = o.[object_id]
        INNER JOIN sys.sysusers su ON o.[schema_id] = su.[UID]
WHERE   ddius.[database_id] = DB_ID() -- current database only 
        AND OBJECTPROPERTY(ddius.[object_id], 'IsUserTable') = 1
        AND ddius.[index_id] > 0
GROUP BY su.[name] ,
        o.[name] ,
        i.[name] ,
        ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] ,
        ddius.[user_updates]
HAVING  ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] = 0
ORDER BY ddius.[user_updates] DESC ,
        su.[name] ,
        o.[name] ,
        i.[name]


-- 可能不高效的非聚集索引 (writes > reads) 
SELECT  OBJECT_NAME(ddius.[object_id]) AS [Table Name] ,
        i.name AS [Index Name] ,
        i.index_id ,
        user_updates AS [Total Writes] ,
        user_seeks + user_scans + user_lookups AS [Total Reads] ,
        user_updates - ( user_seeks + user_scans + user_lookups ) AS [Difference]
FROM    sys.dm_db_index_usage_stats AS ddius WITH ( NOLOCK )
        INNER JOIN sys.indexes AS i WITH ( NOLOCK ) ON ddius.[object_id] = i.[object_id]
                                                       AND i.index_id = ddius.index_id
WHERE   OBJECTPROPERTY(ddius.[object_id], 'IsUserTable') = 1
        AND ddius.database_id = DB_ID()
        AND user_updates > ( user_seeks + user_scans + user_lookups )
        AND i.index_id > 1
ORDER BY [Difference] DESC ,
        [Total Writes] DESC ,
        [Total Reads] ASC;


--没有用于用户查询的索引
SELECT  '[' + DB_NAME() + '].[' + su.[name] + '].[' + o.[name] + ']' AS [statement] ,
        i.[name] AS [index_name] ,
        ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] AS [user_reads] ,
        ddius.[user_updates] AS [user_writes] ,
        ddios.[leaf_insert_count] ,
        ddios.[leaf_delete_count] ,
        ddios.[leaf_update_count] ,
        ddios.[nonleaf_insert_count] ,
        ddios.[nonleaf_delete_count] ,
        ddios.[nonleaf_update_count]
FROM    sys.dm_db_index_usage_stats ddius
        INNER JOIN sys.indexes i ON ddius.[object_id] = i.[object_id]
                                    AND i.[index_id] = ddius.[index_id]
        INNER JOIN sys.partitions SP ON ddius.[object_id] = SP.[object_id]
                                        AND SP.[index_id] = ddius.[index_id]
        INNER JOIN sys.objects o ON ddius.[object_id] = o.[object_id]
        INNER JOIN sys.sysusers su ON o.[schema_id] = su.[UID]
        INNER JOIN sys.[dm_db_index_operational_stats](DB_ID(), NULL, NULL,
                                                       NULL) AS ddios ON ddius.[index_id] = ddios.[index_id]
                                                              AND ddius.[object_id] = ddios.[object_id]
                                                              AND SP.[partition_number] = ddios.[partition_number]
                                                              AND ddius.[database_id] = ddios.[database_id]
WHERE   OBJECTPROPERTY(ddius.[object_id], 'IsUserTable') = 1
        AND ddius.[index_id] > 0
        AND ddius.[user_seeks] + ddius.[user_scans] + ddius.[user_lookups] = 0
ORDER BY ddius.[user_updates] DESC ,
        su.[name] ,
        o.[name] ,
        i.[name]


--识别在行级的锁定和阻塞
SELECT  '[' + DB_NAME(ddios.[database_id]) + '].[' + su.[name] + '].['
        + o.[name] + ']' AS [statement] ,
        i.[name] AS 'index_name' ,
        ddios.[partition_number] ,
        ddios.[row_lock_count] ,
        ddios.[row_lock_wait_count] ,
        CAST (100.0 * ddios.[row_lock_wait_count] / ( ddios.[row_lock_count] ) AS DECIMAL(5,
                                                              2)) AS [%_times_blocked] ,
        ddios.[row_lock_wait_in_ms] ,
        CAST (1.0 * ddios.[row_lock_wait_in_ms] / ddios.[row_lock_wait_count] AS DECIMAL(15,
                                                              2)) AS [avg_row_lock_wait_in_ms]
FROM    sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ddios
        INNER JOIN sys.indexes i ON ddios.[object_id] = i.[object_id]
                                    AND i.[index_id] = ddios.[index_id]
        INNER JOIN sys.objects o ON ddios.[object_id] = o.[object_id]
        INNER JOIN sys.sysusers su ON o.[schema_id] = su.[UID]
WHERE   ddios.row_lock_wait_count > 0
        AND OBJECTPROPERTY(ddios.[object_id], 'IsUserTable') = 1
        AND i.[index_id] > 0
ORDER BY ddios.[row_lock_wait_count] DESC ,
        su.[name] ,
        o.[name] ,
        i.[name]
--识别闩锁等待
SELECT  '[' + DB_NAME() + '].[' + OBJECT_SCHEMA_NAME(ddios.[object_id])
        + '].[' + OBJECT_NAME(ddios.[object_id]) + ']' AS [object_name] ,
        i.[name] AS index_name ,
        ddios.page_io_latch_wait_count ,
        ddios.page_io_latch_wait_in_ms ,
        ( ddios.page_io_latch_wait_in_ms / ddios.page_io_latch_wait_count ) AS avg_page_io_latch_wait_in_ms
FROM    sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ddios
        INNER JOIN sys.indexes i ON ddios.[object_id] = i.[object_id]
                                    AND i.index_id = ddios.index_id
WHERE   ddios.page_io_latch_wait_count > 0
        AND OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
ORDER BY ddios.page_io_latch_wait_count DESC ,
        avg_page_io_latch_wait_in_ms DESC
--识别锁升级
SELECT  OBJECT_NAME(ddios.[object_id], ddios.database_id) AS [object_name] ,
        i.name AS index_name ,
        ddios.index_id ,
        ddios.partition_number ,
        ddios.index_lock_promotion_attempt_count ,
        ddios.index_lock_promotion_count ,
        ( ddios.index_lock_promotion_attempt_count
          / ddios.index_lock_promotion_count ) AS percent_success
FROM    sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ddios
        INNER JOIN sys.indexes i ON ddios.object_id = i.object_id
                                    AND ddios.index_id = i.index_id
WHERE   ddios.index_lock_promotion_count > 0
ORDER BY index_lock_promotion_count DESC;
--与锁争用有关的索引
SELECT  OBJECT_NAME(ddios.object_id, ddios.database_id) AS object_name ,
        i.name AS index_name ,
        ddios.index_id ,
        ddios.partition_number ,
        ddios.page_lock_wait_count ,
        ddios.page_lock_wait_in_ms ,
        CASE WHEN DDMID.database_id IS NULL THEN 'N'
             ELSE 'Y'
        END AS missing_index_identified
FROM    sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) ddios
        INNER JOIN sys.indexes i ON ddios.object_id = i.object_id
                                    AND ddios.index_id = i.index_id
        LEFT OUTER JOIN ( SELECT DISTINCT
                                    database_id ,
                                    object_id
                          FROM      sys.dm_db_missing_index_details
                        ) AS DDMID ON DDMID.database_id = ddios.database_id
                                      AND DDMID.object_id = ddios.object_id
WHERE   ddios.page_lock_wait_in_ms > 0
ORDER BY ddios.page_lock_wait_count DESC;
--丢失索引
SELECT  user_seeks * avg_total_user_cost * ( avg_user_impact * 0.01 ) AS [index_advantage] ,
        dbmigs.last_user_seek ,
        dbmid.[statement] AS [Database.Schema.Table] ,
        dbmid.equality_columns ,
        dbmid.inequality_columns ,
        dbmid.included_columns ,
        dbmigs.unique_compiles ,
        dbmigs.user_seeks ,
        dbmigs.avg_total_user_cost ,
        dbmigs.avg_user_impact
FROM    sys.dm_db_missing_index_group_stats AS dbmigs WITH ( NOLOCK )
        INNER JOIN sys.dm_db_missing_index_groups AS dbmig WITH ( NOLOCK ) ON dbmigs.group_handle = dbmig.index_group_handle
        INNER JOIN sys.dm_db_missing_index_details AS dbmid WITH ( NOLOCK ) ON dbmig.index_handle = dbmid.index_handle
WHERE   dbmid.[database_id] = DB_ID()
ORDER BY index_advantage DESC;
--索引上的碎片超过15%并且索引体积较大（超过500页）的索引。
SELECT  '[' + DB_NAME() + '].[' + OBJECT_SCHEMA_NAME(ddips.[object_id],
                                                     DB_ID()) + '].['
        + OBJECT_NAME(ddips.[object_id], DB_ID()) + ']' AS [statement] ,
        i.[name] AS [index_name] ,
        ddips.[index_type_desc] ,
        ddips.[partition_number] ,
        ddips.[alloc_unit_type_desc] ,
        ddips.[index_depth] ,
        ddips.[index_level] ,
        CAST(ddips.[avg_fragmentation_in_percent] AS SMALLINT) AS [avg_frag_%] ,
        CAST(ddips.[avg_fragment_size_in_pages] AS SMALLINT) AS [avg_frag_size_in_pages] ,
        ddips.[fragment_count] ,
        ddips.[page_count]
FROM    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'limited') ddips
        INNER JOIN sys.[indexes] i ON ddips.[object_id] = i.[object_id]
                                      AND ddips.[index_id] = i.[index_id]
WHERE   ddips.[avg_fragmentation_in_percent] > 15
        AND ddips.[page_count] > 500
ORDER BY ddips.[avg_fragmentation_in_percent] ,
        OBJECT_NAME(ddips.[object_id], DB_ID()) ,
        i.[name]

-----------------------
--监控长时间运行的查询
CREATE EVENT SESSION [Long Running Procedures] ON SERVER  
ADD EVENT sqlserver.module_end(SET collect_statement=(1)
    WHERE ([duration]>(30000000)))  
ADD TARGET package0.event_file 
(SET filename=N'C:\Long Running Queries.xel') 
GO 

ALTER EVENT SESSION [Long Running Procedures] 
ON SERVER 
STATE = start 
--------------

--禁用并行（已设置）
sp_configure 'show advanced options', 1;
GO
RECONFIGURE WITH OVERRIDE;
GO
sp_configure 'max degree of parallelism', 1;
GO
RECONFIGURE WITH OVERRIDE;
GO
--启用快照隔离等级（未设置，需要数据库上无连接，建议重启应用时进行做该操作）
ALTER DATABASE tuniu  SET READ_COMMITTED_SNAPSHOT ON;

--【care 参数？】
--查看数据库启动的参数
exec sp_configure --'xp_cmdshell';