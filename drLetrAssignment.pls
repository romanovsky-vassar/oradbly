select * from bn.faculty_association where email like '%wild%';
select * from bn.faculty_association where home = 'DANC' order by 2;

select * from IA.MULTI_DISC_FACULTY where ACADEMIC_YR = '2016-17' /*pidm = 10270998*/
;
select * from hremp where pidm = 10270998;
select * from fsp_xref_deptorg where org_code = '20050';

desc adw.shared;

update bn.faculty_association
set home = 'DANC', home_org_desc = 'Dance Department'
where pidm = 10270998 and posn = 'FPR009';
commit;


select * from hrbio where id in 
(
'999131984',
'999132165',
'999136005',
'999459038'
);