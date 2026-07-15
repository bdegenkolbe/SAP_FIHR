Declare @SQL as nvarchar(max)
Declare @SQL1 as nvarchar(max)

Drop Table if exists Analysen.dbo.Filter2024

Select distinct FALNR 
into Analysen.dbo.Filter2024
from (

		Select FALNR from replicate.sap.nlei where 2024 between year(IBGDT) and year(IENDT)
		union
		Select FALNR from replicate.sap.nbew where 2024 between year(BWIDT) and year(BWEDT)
		union
		Select FALNR from replicate.sap.NAPX_FAL

	) t1

SET @SQL='';SET @SQL1=''

SET @SQL=Concat('','SELECT @SQL1=COALESCE(@SQL1+N''
			'', N'''') + isnull(''
	Drop Table if exists Analysen.dbo.''+ SourcetableName +''_2024;
	Select t1.* into Analysen.dbo.''+ SourcetableName +''_2024 from replicate.sap.''+ SourcetableName +'' t1''+
									case when SourcetableName in (''NFAL'',''NBEW'',''NLEI'',''NDIA'') then '' join Analysen.dbo.Filter2024 t2 on t1.FALNR=t2.FALNR'' else '''' end + '';'','''')
										from Analysen.dbo.Admin_TabTree 
										where SourceTableDB=''replicate''')

EXEC sp_EXECutesql @SQL, N'@SQL1 nvarchar(max) OUT', @SQL1 OUT;

Print @SQL1		
EXEC(@SQL1);