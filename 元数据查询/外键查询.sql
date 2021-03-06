SELECT 
    外键名称=a.name
    ,主键列ID=b.rkey 
    ,主键列名=(SELECT name FROM syscolumns WHERE colid=b.rkey AND id=b.rkeyid) 
    ,外键表ID=b.fkeyid 
    ,外键表名称=object_name(b.fkeyid) 
    ,外键列ID=b.fkey 
    ,外键列名=(SELECT name FROM syscolumns WHERE colid=b.fkey AND id=b.fkeyid) 
    ,级联更新=ObjectProperty(a.id,'CnstIsUpdateCascade') 
    ,级联删除=ObjectProperty(a.id,'CnstIsDeleteCascade') 
	,是否禁用 = (select top 1 bb.is_disabled from sys.foreign_keys bb where bb.name=a.name)
	,禁用约束SQL='alter table '+object_name(b.fkeyid)+' NOCHECK CONSTRAINT '+a.name+' ;'
	,启用约束SQL='alter table '+object_name(b.fkeyid)+' CHECK CONSTRAINT '+a.name+' ;'
FROM sysobjects a 
    join sysforeignkeys b on a.id=b.constid 
    join sysobjects c on a.parent_obj=c.id 
where a.xtype='f' AND c.xtype='U' 
   -- and object_name(b.rkeyid)='sys_table'; --Table name
    and object_name(b.fkeyid)='sys_column'
--sys_column ->CONSTRAINT sys_column$FK_TBL_ID ->sys_table