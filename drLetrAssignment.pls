create or replace PACKAGE BODY drLetrAssignment
AS

cursor c1 is
(
select distinct to_char(agbgift_entry_date,'DD-MON-YYYY') entryDate, agvglst_gift_no giftNum, agvglst_pledge_no pldgNum,
       agbgift_pidm pidm, a.apbcons_pref_clas classYr, agvglst_campaign camp, agvglst_desg desg, '' pldg_status, agvglst_gcls_code clsCode,
       agvglst_gift_code giftCode, agvglst_amt AmtDesg, 
                             (select sum(z.agvglst_amt)
                             from agvglst z
                             where z.agvglst_gift_no = c.agvglst_gift_no and
                                   substr(agvglst_desg,1,2) = 'AF') afAmtTotal, 
       agrgmlt_credit xrefCredit, agbgift_amt_tot AmtTotal, agvplst_amt_pledged totAmtPldg, agrgmlt_xref_pidm xrefPidm, 
       b.apbcons_pref_clas xrefClassYr, agvglst_fisc_code fy
from agbgift, agvglst c, agvplst d, apbcons a, apbcons b, agrgmlt
where agvglst_pidm = agbgift_pidm and agvglst_gift_no = agbgift_gift_no and 
      agvglst_pidm = agrgmlt_pidm(+) and agvglst_gift_no = agrgmlt_gift_no(+) and
      agvglst_pidm = agvplst_pidm(+) and agvglst_pledge_no = agvplst_pledge_no(+) and
      agvglst_pidm = a.apbcons_pidm(+) and agrgmlt_xref_pidm = b.apbcons_pidm(+) and
      agbgift_entry_date >= (sysdate-7)
      -- testing
      --and agbgift_pidm = '20008577'
      --and agvglst_gift_no = '0564256'
UNION
select distinct to_char(agbpldg_entry_date,'DD-MON-YYYY') entryDate, '' giftNum, agbpldg_pledge_no pldgNum,
       agbpldg_pidm pidm, a.apbcons_pref_clas classYr, agvplst_campaign camp, agvplst_desg desg, agvplst_psta_code pldg_status, 
       agvplst_pcls_code clsCode, agvplst_pldg_code giftCode, agvplst_amt AmtDesg, 
                             (select sum(z.agvplst_amt)
                             from agvplst z
                             where z.agvplst_pledge_no = c.agvplst_pledge_no and
                                   substr(agvplst_desg,1,2) = 'AF') afAmtTotal, 
       agrpmlt_credit xrefCredit, agbpldg_amt_pledged AmtTotal, agvplst_amt_pledged totAmtPldg, agrpmlt_xref_pidm xrefPidm, 
       b.apbcons_pref_clas xrefClassYr, agvplst_fisc_code fy
from agbpldg, agvplst c, apbcons a, apbcons b, agrpmlt
where agbpldg_pidm = agvplst_pidm and agbpldg_pledge_no = agvplst_pledge_no and 
      agbpldg_pidm = agrpmlt_pidm(+) and agbpldg_pledge_no = agrpmlt_pledge_no(+) and
      agbpldg_pidm = a.apbcons_pidm(+) and agrpmlt_xref_pidm = b.apbcons_pidm(+) and  
      agbpldg_entry_date >= (sysdate-7)
      -- testing
      --and agbpldg_pidm = '20008577' 
      --and agvplst_pledge_no = '0564256'
)
order by 1,2,7;

type dtC1 is table of c1%ROWTYPE; 
allGPData dtC1;
currFY                number;

workingPidm           adw.ack_letters.AL_PIDM%TYPE;
workingXrefPidm       adw.ack_letters.AL_PIDM%TYPE;
globalOBOName         adw.giftpldg.FROM_TO_NAMES%Type := '';
workingCY             alumni.apbcons.apbcons_pref_clas%TYPE;         
workingCC             adw.shared.const_codes%TYPE;
currDonorCode         adw.shared.const_codes%TYPE;
currRYear             boolean;
currLRYear            boolean;
currPrevAmts          number;
currPrevAmts3YR       number;
isOneToFiveOut        boolean;
isSixToTenOut         boolean;
isMostRecentGrad      boolean;
isFirstEverGift       boolean;
min15                 number := 250;
min610                number := 500;
minOver10             number := 1000;
isPldgAndFirstPay     boolean := false;
isCompPldg            boolean := false;
isStraightPldg        boolean := false;
--isHardshipGift        boolean := false;
finalLetrCode         adw.ack_letters.AL_LETR_CODE%TYPE;
finalLetrDesc         adw.ack_letters.AL_LETR_DESC%TYPE;
notAssigned           boolean := true;
tName                 adw.ack_letters.al_name_list%TYPE;
recentEvntInd         varchar2(1) := '';

-- junk -- >  
tCY                   adw.ack_letters.al_class_yr%TYPE;
tCYS                  adw.ack_letters.al_class_yr%TYPE;    
tGY                   adw.ack_letters.al_class_yr%TYPE;

/* ------------------------------------------------------------------------------------------------ */
FUNCTION getRecentEvnts(pidmIn in number) RETURN VARCHAR2
IS
locCurrEvnt varchar2(1) := '';
BEGIN
 begin
 select distinct 'Y'
 INTO locCurrEvnt
 from gerattd b, ssrmeet c
 where pidmIn = b.GERATTD_PIDM and  b.GERATTD_FUNC_CODE = 'PROGRAM'
      and b.GERATTD_EVNT_CRN = c.SSRMEET_CRN and c.ssrmeet_term_code = 'EVENT'
      and c.SSRMEET_START_DATE >= sysdate-90
;
 EXCEPTION WHEN NO_DATA_FOUND THEN
       locCurrEvnt := ''; 

 end;

return locCurrEvnt;
END getRecentEvnts;

FUNCTION getDonorCode(pidmIn in number) RETURN VARCHAR2
IS
locDonorCodes    adw.shared.const_codes%TYPE;
BEGIN
 begin
  select const_codes into locDonorCodes 
  from adw.shared where shared_pidm = pidmIn;
  exception
     when no_data_found then
         locDonorCodes := '';
 end;
         
return locDonorCodes;
END getDonorCode;

FUNCTION chkIfStock(giftIn in varchar2) RETURN VARCHAR2
IS
locTest   varchar2(1) := '';
BEGIN
begin
  Select 'Y' INTO locTest From adw.giftpldg z Where
     z.gift_num = giftIn and z.AGRGAUX_DESC like 'STOCK%'; 
  EXCEPTION 
     WHEN NO_DATA_FOUND THEN locTest := 'N';
     WHEN TOO_MANY_ROWS THEN locTest := 'Y';
end;

return locTest;

END chkIfStock;

FUNCTION chkPldgFirstPay(pldgIn in varchar2, indexIn in number) RETURN BOOLEAN
IS
testGiftDate  date;
testGiftNum   agvglst.agvglst_gift_no%TYPE;
testPldgDate  date;
isSameWeek    boolean := false;

BEGIN

begin 
  select distinct to_date(to_char(agvplst_pledge_date,'DD-MON-YYYY'),'DD-MON-YYYY') 
  into testPldgDate 
  from agvplst where agvplst_pledge_no = pldgIn;
  exception when no_data_found then
     testPldgDate := '';
end;
 begin
   select distinct MAX(to_date(to_char(a.agvglst_gift_date,'DD-MON-YYYY'),'DD-MON-YYYY')),
                          a.agvglst_gift_no 
   into testGiftDate, testGiftNum
   from agvglst a 
   where a.agvglst_pledge_no = pldgIn and 
         a.agvglst_gift_no = (Select MAX(z.agvglst_gift_no)
                              From agvglst z
                              Where z.agvglst_pidm = a.agvglst_pidm and
                                    z.agvglst_pledge_no = a.agvglst_pledge_no)
   group by a.agvglst_gift_no; 
   exception when no_data_found then
     testGiftDate := '';
 end;

if testGiftDate is not null and testPldgDate is not null then
  if ((testGiftDate - testPldgDate) <= 7) then
     isSameWeek := true;
     allGPData(indexIn).giftnum := testGiftNum;
  end if;
end if;

return isSameWeek;

END chkPldgFirstPay;

FUNCTION chkCompPldg(pldgIn in varchar2) RETURN BOOLEAN
IS
testComp       varchar2(1);
isCompPldg     boolean := true;

BEGIN
begin
 select distinct 'Y' into testComp from agvplst a
 where a.agvplst_pledge_no = pldgIn and 
      (a.agvplst_amt_pledged - (select sum(z.agvplst_amt_paid) from agvplst z
                                where z.agvplst_pidm = a.agvplst_pidm and
                                      z.agvplst_pledge_no = a.agvplst_pledge_no)  
      ) = 0;
 exception when 
     no_data_found then
        isCompPldg := false;
end;

return isCompPldg;

END chkCompPldg;

FUNCTION chkOneFive(inCY IN VARCHAR2) RETURN BOOLEAN
IS
 testYr      varchar2(1);
 locIs15     boolean := true; 
BEGIN
  begin
    select Distinct 'Y' INTO testYr from dual
    where inCY >= currFY-5 and inCY <= currFY-1; 
	EXCEPTION
    WHEN NO_DATA_FOUND THEN
        locIs15 := false;         
  end;
  
Return locIs15;

END chkOneFive;

FUNCTION chkSixTen(inCY IN VARCHAR2) RETURN BOOLEAN
IS
 testYr      varchar2(1);
 locIs610    boolean := true; 
BEGIN
  begin
    select Distinct 'Y' INTO testYr from dual
    where inCY >= currFY-10 and inCY <= currFY-6; 
	EXCEPTION
    WHEN NO_DATA_FOUND THEN
        locIs610 := false;         
  end;
  
Return locIs610;

END chkSixTen;

FUNCTION chkMostRecentGrad(inCY IN VARCHAR2) RETURN BOOLEAN
IS
 testYr         varchar2(1);
 locIsRecent    boolean := true; 
BEGIN
  begin
    select Distinct 'Y' INTO testYr from dual
    where inCY = (currFY-1); 
	EXCEPTION
    WHEN NO_DATA_FOUND THEN
        locIsRecent := false;         
  end;
  
Return locIsRecent;

END chkMostRecentGrad;

FUNCTION chkIfFirst(inPidm in number, inGiftNum in varchar2) RETURN BOOLEAN
IS
testFirst  varchar2(1);
locResult  boolean := true;
BEGIN
  begin
   select distinct 'Y' into testFirst from agvglst a, adw.shared b
   where a.agvglst_pidm = b.shared_pidm and a.agvglst_pidm = inPidm and 
         a.agvglst_gift_no = inGiftNum and
         a.agvglst_gift_no = (Select MIN(z.agvglst_gift_no) from agvglst z
                              Where z.agvglst_pidm = a.agvglst_pidm)
         and agvglst_desg != 'JG101' and b.class_yr_sort >= 1980
         and (b.CONST_CODES like 'ALUM' or b.CONST_CODES like 'ALND');
   EXCEPTION 
       WHEN NO_DATA_FOUND THEN
          locResult := false;
  end;
  
  Return locResult;
  
END chkIfFirst;

FUNCTION isReunion(inCY IN VARCHAR2) RETURN BOOLEAN
IS
 testYr      varchar2(1);
 locIsR      boolean := true; 
BEGIN
  begin
    select Distinct 'Y' INTO testYr from dual
    where inCY in ('2012', '2002', '1997', '1987', '1982', '1972', '1962', '1957','1952',
	               '1947', '1942', '1937','2008', '2009', '1993', '1994', '1978', '1979',
				   '1968', '1969'); 
	EXCEPTION
    WHEN NO_DATA_FOUND THEN
        locIsR := false;         
  end;
  
Return locIsR;

END isReunion;

FUNCTION isReunionCP(inCY IN VARCHAR2) RETURN BOOLEAN
IS
 testYr      varchar2(1);
 locIsR      boolean := true; 
BEGIN
  begin
    select Distinct 'Y' INTO testYr from dual
    where inCY in ('2012', '2002', '1997', '1987', '1982', '1972', '1962', '1957','1952',
	               '1947', '1942', '1937'); 
	EXCEPTION
    WHEN NO_DATA_FOUND THEN
        locIsR := false;         
  end;
  
Return locIsR;

END isReunionCP;

FUNCTION isLandMarkReunion(inCY IN VARCHAR2) RETURN BOOLEAN
IS
 testYr      varchar2(1);
 locIsLR     boolean := true;
BEGIN
  begin
    select Distinct 'Y' INTO testYr from dual
    where inCY in ('1967','1977','1992','2007');
	EXCEPTION
    WHEN NO_DATA_FOUND THEN
        locIsLR := false;         
  end;
  
Return locIsLR;
END isLandMarkReunion;

FUNCTION dConstCodes(pidmIn in number)
RETURN varchar2
IS
locConstCodes     adw.shared.const_codes%TYPE;

BEGIN

begin
select const_codes into locConstCodes from adw.shared where shared_pidm = pidmIn; exception when no_data_found then locConstCodes := '';
end;

return locConstCodes;

END dConstCodes;

FUNCTION checkOBO(pidmIn in number, giftIn in varchar2, pldgIn in varchar2, xrefIn in varchar2)
RETURN BOOLEAN
IS
holdOBO   varchar2(3);
locIsOBO  boolean := true;

BEGIN
if giftIn is not null then
 begin
 select distinct from_to_names into globalOBOName 
 from adw.giftpldg where gift_num = giftIn and 
 /*xref_pidm = xrefIn and*/ obo_giver_ind = 'Y' and gp_pidm = pidmIn and substr(from_to_names,1,3) = 'OBO';
 exception 
   when no_data_found then
      locIsOBO := false;
 end;  
else
  if pldgIn is not null and giftIn is null then
    begin
    select distinct from_to_names into globalOBOName 
    from adw.giftpldg where pldg_num = pldgIn and 
    /*xref_pidm = xrefIn and*/ obo_giver_ind = 'Y' and gp_pidm = pidmIn and substr(from_to_names,1,3) = 'OBO';
    exception 
      when no_data_found then
         locIsOBO := false;
    end;
  end if;
end if;

return locIsOBO;

END checkOBO;

FUNCTION PrevChk(inPidm IN VARCHAR2, inGiftDate IN DATE,
                      pldgNumIn in varchar2) RETURN NUMBER
IS
locAmt1     NUMBER := 0;
locAmt2     NUMBER := 0;
locAmt3     NUMBER := 0;
locAmt4     NUMBER := 0;
locAmt5     NUMBER := 0;
locTotalAmt NUMBER := 0;

BEGIN -- Gets stuff from THIS FY -- >   

begin
-- paid-up pledges from the year  
   begin
    select Distinct a.agvplst_amt_pledged
    INTO locAmt1 
    from agvplst a, agvglst b
    where a.agvplst_pidm = inPidm and a.agvplst_pidm = b.agvglst_pidm and
          b.agvglst_pledge_no = a.agvplst_pledge_no and a.agvplst_pledge_no != '0000000' and
          b.agvglst_gift_no = (Select max(z.agvglst_gift_no)
                               from agvglst z
                               where z.agvglst_pidm = b.agvglst_pidm and z.agvglst_gift_no = 
                                     b.agvglst_gift_no
                              ) and
          a.agvplst_fisc_code = currFY and
          a.agvplst_desg in ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH',
                                   'AFALM','AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
          a.agvplst_psta_code = 'P' and
          a.agvplst_pledge_no not in (pldgNumIn);
     exception when no_data_found then
              locAmt1 := 0;
               when too_many_rows then
              locAmt1 := 0;
   end;

-- existing Pledge payments of this pledge (if it's a pledge)  
   begin
   select Distinct decode(sum(a.agvglst_amt),null,0,sum(a.agvglst_amt)) 
   INTO locAmt5 
    from agvglst a, agbgift b
    where a.agvglst_pidm = inPidm and 
          a.agvglst_pidm = b.agbgift_pidm and a.agvglst_gift_no = b.agbgift_gift_no and
          a.agvglst_pledge_no = pldgNumIn and
          a.agvglst_desg in ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH','AFALM',
                               'AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
          to_date(to_char(b.agbgift_entry_date,'DD-MON-YYYY'),'DD-MON-YYYY') < inGiftDate;
   end;

-- Any outright giver data (gifts)  
    begin
    select Distinct decode(sum(a.agvglst_amt),null,0,sum(a.agvglst_amt)) 
    INTO locAmt2 
    from agvglst a, agbgift b
    where a.agvglst_pidm = inPidm and 
	      a.agvglst_pidm = b.agbgift_pidm and a.agvglst_gift_no = b.agbgift_gift_no and
	      a.agvglst_fisc_code = currFY and a.agvglst_pledge_no = '0000000' and
	      a.agvglst_desg in ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH',
                                   'AFALM','AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
		  to_date(to_char(b.agbgift_entry_date,'DD-MON-YYYY'),'DD-MON-YYYY') < inGiftDate;
    end;

-- Any XREF recvr data 									   
    begin
    select Distinct decode(sum(b.agrgmlt_credit),null,0,sum(b.agrgmlt_credit)) 
    INTO locAmt3 
    from agrgmlt b
	where b.agrgmlt_xref_pidm = inPidm and
	      b.agrgmlt_gift_no in (select c.agvglst_gift_no from agvglst c, agbgift d
		                        where  c.agvglst_pidm = d.agbgift_pidm and c.agvglst_gift_no = d.agbgift_gift_no and
                                       c.agvglst_gift_no = b.agrgmlt_gift_no and
                                       c.agvglst_fisc_code = currFY
								       and c.agvglst_desg in 
									       ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH',
                                                'AFALM','AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
									   to_date(to_char(d.agbgift_entry_date,'DD-MON-YYYY'),'DD-MON-YYYY') < 
                                       to_date(to_char((inGiftDate),'DD-MON-YYYY'),'DD-MON-YYYY'));
    end;
    
-- Matches on pledge/payments on pledges that have been paid this FY 
    begin
    select decode(sum(z.agbmgid_amt),null,0,sum(z.agbmgid_amt))
    INTO locAmt4
    from agbmgid z, agvglst a
    where a.agvglst_pidm = z.agbmgid_empl_pidm   and agbmgid_empl_pidm = inPidm and
          a.agvglst_gift_no = z.agbmgid_empl_gift_no and a.agvglst_pledge_no in 
                    (
                    select Distinct a.agvplst_pledge_no
                    from agvplst a, agvglst b
                    where a.agvplst_pidm = inPidm and a.agvplst_pidm = b.agvglst_pidm and
                          b.agvglst_pledge_no = a.agvplst_pledge_no and a.agvplst_pledge_no != '0000000' and
                          b.agvglst_gift_no = (Select max(z.agvglst_gift_no)
                                               from agvglst z
                                               where z.agvglst_pidm = b.agvglst_pidm and z.agvglst_gift_no = 
                                                     b.agvglst_gift_no
                                              ) and
                          b.agvglst_fisc_code = currFY and
                          a.agvplst_desg in ('AFFAC','AFATH','AFCAM','AFLIB','AFRES',
                                                 'AFSCH','AFALM','AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
                          a.agvplst_psta_code = 'P' -- paid pledge 
                    )
           and z.agbmgid_status = 'P'; -- paid match  
    end;
end;

locTotalAmt := locAmt1 + locAmt2 + locAmt3 + locAmt4 + locAmt5;

--dbms_output.put_line('prev amt1: ' || locAmt1);
--dbms_output.put_line('prev amt2: ' || locAmt2);
--dbms_output.put_line('prev amt3: ' || locAmt3);
--dbms_output.put_line('prev amt4: ' || locAmt4);

Return locTotalAmt;
END PrevChk;

FUNCTION PrevChk3YR(inPidm IN VARCHAR2, inGiftDate IN DATE) RETURN NUMBER
IS
locAmt1     NUMBER;
locAmt2     NUMBER;
locTotalAmt NUMBER;

BEGIN -- Gets stuff from last 3 FY (LandMark people) ----- >   

begin
-- Any outright giver data 
    select Distinct decode(sum(a.agvglst_amt),null,0,sum(a.agvglst_amt)) 
    INTO locAmt1 
    from agvglst a, agbgift b
    where a.agvglst_pidm = inPidm and 
	      a.agvglst_pidm = b.agbgift_pidm and a.agvglst_gift_no = b.agbgift_gift_no and
	  (a.agvglst_fisc_code = currFY or a.agvglst_fisc_code = (currFY-1) or a.agvglst_fisc_code = (currFY-2))
	      and a.agvglst_desg in ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH','AFALM',
                                     'AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
		  to_date(to_char(b.agbgift_entry_date,'DD-MON-YYYY'),'DD-MON-YYYY') < inGiftDate;

-- Any XREF recvr data 									   
    select Distinct decode(sum(b.agrgmlt_credit),null,0,sum(b.agrgmlt_credit)) 
    INTO locAmt2 
    from agrgmlt b
	where b.agrgmlt_xref_pidm = inPidm and
	      b.agrgmlt_gift_no in (select c.agvglst_gift_no from agvglst c, agbgift d
		                        where  c.agvglst_pidm = d.agbgift_pidm and c.agvglst_gift_no = d.agbgift_gift_no and
                                       c.agvglst_gift_no = b.agrgmlt_gift_no and
                                       (c.agvglst_fisc_code = currFY or c.agvglst_fisc_code = (currFY-1) 
                                        or c.agvglst_fisc_code = (currFY-2))
								       and c.agvglst_desg in 
									       ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH','AFALM',
                                                 'AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
									   to_date(to_char(d.agbgift_entry_date,'DD-MON-YYYY'),'DD-MON-YYYY') < 
                                       to_date(to_char((inGiftDate),'DD-MON-YYYY'),'DD-MON-YYYY'));
end;

locTotalAmt := locAmt1 + locAmt2;

Return locTotalAmt;
END PrevChk3YR;

FUNCTION PrevFYChk(inPidm IN VARCHAR2, inFY IN VARCHAR2)
                          RETURN NUMBER
IS
locAmt1     NUMBER;
locAmt2     NUMBER;
locTotalAmt NUMBER;

BEGIN -- Gets Last FYs stuff ----->   

begin
-- Any outright giver data 
    select Distinct decode(sum(a.agvglst_amt),null,0,sum(a.agvglst_amt)) INTO locAmt1 from agvglst a
    where a.agvglst_pidm = inPidm and 
	      a.agvglst_fisc_code = inFY and
	      a.agvglst_desg in ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH','AFALM',
                                'AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF');
          									   
-- Any XREF recvr data 									   
    select Distinct decode(sum(b.agrgmlt_credit),null,0,sum(b.agrgmlt_credit)) INTO locAmt2 from agrgmlt b
	where b.agrgmlt_xref_pidm = inPidm and
	      b.agrgmlt_gift_no in (select c.agvglst_gift_no from agvglst c
		                        where  c.agvglst_gift_no = b.agrgmlt_gift_no and
                                       c.agvglst_fisc_code = inFY and
								       c.agvglst_desg in 
									       ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH','AFALM',
                                               'AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
									   c.agvglst_pledge_no = '0000000');
end;

locTotalAmt := locAmt1 + locAmt2;

Return locTotalAmt;
END PrevFYChk;

FUNCTION findGiftSociety(inAmt in number) RETURN VARCHAR2
IS
locLetrDesc  adw.ack_letters.AL_LETR_DESC%TYPE := '';
locAmt       NUMBER;

BEGIN
locAmt := inAmt;
case
when locAmt < 1000 and locAmt > 0           THEN locLetrDesc := 'Cornaro Fellows'; 
when locAmt >= 1000 and locAmt <= 2499      THEN locLetrDesc := 'Salve Society';
when locAmt >= 2500 and locAmt <= 4999      THEN locLetrDesc := 'Matthew Vassar Associates';
when locAmt >= 5000 and locAmt <= 9999      THEN locLetrDesc := 'Magnificent Enterprise';
when locAmt >= 10000 and locAmt <= 24999    THEN locLetrDesc := 'Gaudeamus Society';
when locAmt >= 25000 and locAmt <= 49999    THEN locLetrDesc := 'Main Circle';
when locAmt >= 50000                        THEN locLetrDesc := 'President''s Circle';
else                                             locLetrDesc := '';
end case;

Return locLetrDesc;
END;

FUNCTION chkGiftNumCycle(inPidm IN VARCHAR2, inGiftDate IN DATE)
                                RETURN NUMBER
IS
locCnt1      NUMBER;
locCnt2      NUMBER;
locCnt3      NUMBER;
locTotalCnt  NUMBER;

BEGIN

begin
-- Any outright giver data 
    select count(distinct a.agvglst_gift_no) INTO locCnt1 from agvglst a, agbgift b
    where a.agvglst_pidm = inPidm and 
	      a.agvglst_pidm = b.agbgift_pidm and a.agvglst_gift_no = b.agbgift_gift_no and
	      a.agvglst_fisc_code = currFY and
	      a.agvglst_desg in ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH','AFALM','AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
		  to_date(to_char(b.agbgift_entry_date,'DD-MON-YYYY'),'DD-MON-YYYY') < 
              to_date(to_char(inGiftDate,'DD-MON-YYYY'),'DD-MON-YYYY') and
		  a.agvglst_pledge_no = '0000000';

-- Any paid pledges	
    select count(distinct a.agvplst_pledge_no) INTO locCnt3 from agvplst a, agbpldg b
    where a.agvplst_pidm = inPidm and 
          a.agvplst_pidm = b.agbpldg_pidm and a.agvplst_pledge_no = b.agbpldg_pledge_no and
          a.agvplst_fisc_code = currFY and
          a.agvplst_desg in ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH','AFALM','AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
          to_date(to_char(b.agbpldg_entry_date,'DD-MON-YYYY'),'DD-MON-YYYY') < 
              to_date(to_char(inGiftDate,'DD-MON-YYYY'),'DD-MON-YYYY') and
          a.agvplst_psta_code = 'P';
          								   
-- Any XREF recvr data 									   
    select count(distinct b.agrgmlt_gift_no) INTO locCnt2 from agrgmlt b
	where b.agrgmlt_xref_pidm = inPidm and
	      b.agrgmlt_gift_no in (select d.agvglst_gift_no from agbgift c, agvglst d
		                        where  c.agbgift_fisc_code = currFY and
                                       c.agbgift_pidm = d.agvglst_pidm and c.agbgift_gift_no = d.agvglst_gift_no and
                                       d.agvglst_pledge_no = '0000000' and d.agvglst_desg in 
									      ('AFFAC','AFATH','AFCAM','AFLIB','AFRES','AFSCH','AFALM',
                                             'AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') and
									   to_date(to_char(c.agbgift_entry_date,'DD-MON-YYYY'),'DD-MON-YYYY') < 
                                            to_date(to_char((inGiftDate),'DD-MON-YYYY'),'DD-MON-YYYY'));

locTotalCnt := locCnt1 + locCnt2 + locCnt3 + 1;
end;

Return locTotalCnt;
END chkGiftNumCycle;

FUNCTION WaitMatchChk(inPidm IN VARCHAR2, inXrefPidm in varchar2, inGiftNo IN VARCHAR2) RETURN NUMBER 
IS
locMgAmt        alumni.agbmgid.agbmgid_amt%TYPE := 0;

BEGIN
begin
	Select decode(sum(z.agbmgid_amt),null,0,sum(z.agbmgid_amt))
	InTo locMgAmt
	from agbmgid z
    where z.agbmgid_empl_pidm in (inPidm, inXrefPidm) and
          z.agbmgid_empl_gift_no = inGiftNo and
		  (z.agbmgid_status is null OR z.agbmgid_activity_date like
                                  (Select agvglst_gift_date
		                           FROM agvglst
								   Where agvglst_pidm in (inPidm, inXrefPidm) and
								         agvglst_gift_no = inGiftNo))
    ;
    EXCEPTION
	WHEN NO_DATA_FOUND THEN
	  locMgAmt := 0;
	WHEN OTHERS THEN
	  locMgAmt := 0; 		  
   end;
   
Return locMgAmt; 
END WaitMatchChk;

PROCEDURE swapDesgDescs
IS
BEGIN

Update adw.ack_letters 
Set al_desg_desc = 'the College''s greatest needs' Where al_desg in ('AFALM','AFPAF','AFALMVF','AFPAFVF') and
    al_letr_code in ('02L','02LA','02AF','02CPL','02CPL-R','02CPL-LR','04PALM.2','04PRNT.2','04FRND.2', '01L', '01LA', '01PL', '01PL-R', '03AF', '04PALM', '04PRNT', '04FRND'
);
Update adw.ack_letters 
Set al_desg_desc = 'Vassar''s greatest needs' Where al_desg in ('AFALMVF') and
    al_letr_code in 
       ('01', '01AF');

Update adw.ack_letters Set al_desg_desc = 'athletics' Where al_desg in ('AFATH','AFATHVF');
Update adw.ack_letters Set al_desg_desc = 'campus preservation' Where al_desg in ('AFCAM','AFCAMVF');
Update adw.ack_letters Set al_desg_desc = 'faculty salaries and research' Where al_desg in ('AFFAC','AFFACVF');
Update adw.ack_letters Set al_desg_desc = 'the library program' Where al_desg in ('AFLIB','AFLIBVF');
Update adw.ack_letters Set al_desg_desc = 'residential life' Where al_desg in ('AFRES','AFRESVF');
Update adw.ack_letters Set al_desg_desc = 'scholarships' Where al_desg in ('AFSCH','AFSCHVF');
Update adw.ack_letters Set al_desg_desc = 'sustainability' Where al_desg in ('AFSUS','AFSUSVF');

commit;

Update adw.ack_letters a Set a.al_desg_desc = (Select b.adbdesg_name From adbdesg b
                                               Where b.adbdesg_desg = a.al_desg)
Where a.al_desg_desc is null;
commit;

END swapDesgDescs;

PROCEDURE updateOtherXrefData
AS
cursor c1 is select al_pidm, al_gift_num 
from adw.ack_letters where al_xref_from_to is null
and al_gift_num is not null;
cursor c2 is select al_pidm, al_pldg_num
from adw.ack_letters where al_xref_from_to is null
and al_gift_num is null;

type dtC1 is table of c1%rowtype;
type dtC2 is table of c2%rowtype;

locC1 dtC1;
locC2 dtC2;

BEGIN
open c1; 
fetch c1 bulk collect into locC1;
if locC1.first is not null then
if locC1(1).al_pidm is not null THEN
 FOR i in locC1.FIRST..locC1.LAST LOOP
   begin
     update adw.ack_letters 
    set al_xref_from_to = concatRows('select trim(x.from_to_names || decode(z.agrgasc_assc_code,''MEMRY'','' DOD: '', null) || to_char(y.DEATH_DATE,''MM/DD/YYYY'')) 
                                                         from agrgasc z, adw.bio y, adw.giftpldg x
                                                         where z.agrgasc_pidm = ' || locC1(i).al_pidm || ' and z.agrgasc_assc_pidm = y.bio_pidm(+) and 
                                                              z.agrgasc_gift_no = ''' || locC1(i).al_gift_num || ''' and z.agrgasc_assc_code in (''MEMRY'',''HONOR'') and
                                                              z.agrgasc_pidm = x.gp_pidm and z.agrgasc_gift_no = x.gift_num')
    where al_pidm = locC1(i).al_pidm and al_gift_num = locC1(i).al_gift_num and locC1(i).al_gift_num != '0568355'; 
   end; /* concatRows() : baninst1 function */       
 END LOOP;
end if;
end if;
close c1;
--------------------> 
open c2; 
fetch c2 bulk collect into locC2;
if locC2.first is not null then
if locC2(1).al_pidm is not null THEN
 FOR i in locC2.FIRST..locC2.LAST LOOP
   begin
    update adw.ack_letters 
    set al_xref_from_to = concatRows('select trim(x.from_to_names || decode(z.agrpasc_assc_code,''MEMRY'','' DOD: '', null) || to_char(y.DEATH_DATE,''MM/DD/YYYY'')) 
from agrpasc z, adw.bio y, adw.giftpldg x
where z.agrpasc_pidm = ' || locC2(i).al_pidm || ' and z.agrpasc_assc_pidm = y.bio_pidm(+) and 
          z.agrpasc_pledge_no = ''' || locC2(i).al_pldg_num || ''' and z.agrpasc_assc_code in (''MEMRY'',''HONOR'') and
          z.agrpasc_pidm = x.gp_pidm and z.agrpasc_pledge_no = x.pldg_num')
    where al_pidm = locC2(i).al_pidm and al_pldg_num = locC2(i).al_pldg_num; 
   end;
 END LOOP;
end if;
end if;
close c2;

commit;

END updateOtherXrefData;

PROCEDURE updateChildData
IS

type dtPidm is table of adw.ack_letters.al_pidm%TYPE;
type dtGiftNum is table of adw.ack_letters.al_gift_num%TYPE; 
locPidm    dtPidm;              
locGiftNo  dtGiftNum;        

locChld1CY          adw.bio.CHILD_1_CLS_YR%TYPE;
locChld2CY          adw.bio.CHILD_2_CLS_YR%TYPE;
locChld3CY          adw.bio.CHILD_3_CLS_YR%TYPE;
locChld4CY          adw.bio.CHILD_4_CLS_YR%TYPE;
locChld1Pidm        adw.bio.CHILD_PIDM_1%TYPE;
locChld1Name        adw.bio.CHILD_NAME_1%TYPE;
locChld1Gender      adw.bio.CHILD_1_GENDER%TYPE;
locChld2Pidm        adw.bio.CHILD_PIDM_1%TYPE;
locChld2Name        adw.bio.CHILD_NAME_1%TYPE;
locChld2Gender      adw.bio.CHILD_1_GENDER%TYPE;
locChld3Pidm        adw.bio.CHILD_PIDM_1%TYPE;
locChld3Name        adw.bio.CHILD_NAME_1%TYPE;
locChld3Gender      adw.bio.CHILD_1_GENDER%TYPE;
locChld4Pidm        adw.bio.CHILD_PIDM_1%TYPE;
locChld4Name        adw.bio.CHILD_NAME_1%TYPE;
locChld4Gender      adw.bio.CHILD_1_GENDER%TYPE;

insrtCnt            number(1) := 0;

BEGIN
begin
  select DISTINCT al_pidm, al_gift_num
  BULK COLLECT INTO locPidm, locGiftNo
  from adw.ack_letters where al_letr_code in ('04PRNT','04PRNT.2');
  EXCEPTION 
    WHEN NO_DATA_FOUND THEN
       locPidm(1) := '';
end;
	 
If locPidm.FIRST is not null THEN
  FOR i IN locPidm.FIRST..locPidm.LAST
  LOOP
   begin 
     Select child_1_cls_yr, child_2_cls_yr, child_3_cls_yr, child_4_cls_yr
     INTO locChld1CY,locChld2CY,locChld3CY,locChld4CY
     From adw.bio
     Where bio_pidm = locPidm(i);
     EXCEPTION 
        WHEN NO_DATA_FOUND THEN 
	        locChld1CY := '';
		    locChld2CY := '';
		    locChld3CY := '';
		    locChld4CY := '';
   end;
   if locChld1CY >= currFY and locChld1CY <= currFY+3 THEN    
     If insrtCnt < 2 Then
       begin
	      Select b.child_pidm_1, b.child_name_1, a.gender
		  INTO locChld1Pidm, locChld1Name, locChld1Gender 
		  From bn.rtfiles a, adw.bio b
		  Where b.bio_pidm = locPidm(i) and b.child_pidm_1 = a.pidm and
		        a.cur_term = 'Y';
		  EXCEPTION
		     WHEN NO_DATA_FOUND THEN
			     locChld1Pidm := '';
				 locChld1Name := '';
				 locChld1Gender := '';
	   end;       
	      if insrtCnt = 0 Then
	      begin
		    UPDATE adw.ack_letters 
               SET al_child1_pidm = locChld1Pidm, al_child1_name = locChld1Name,
		           al_child1_gender = locChld1Gender
	        WHERE al_pidm = locPidm(i);
		  end;
		  else
		   if insrtCnt = 1 Then
		   begin
		     UPDATE adw.ack_letters 
             SET al_child2_pidm = locChld1Pidm, al_child2_name = locChld1Name,
		         al_child2_gender = locChld1Gender
	         WHERE al_pidm = locPidm(i);
           end;
		   end if;										   
		  end if;
		  insrtCnt := insrtCnt + 1;
     End if;
   end if;
   if locChld2CY >= currFY and locChld2CY <= currFY+3 THEN    
     If insrtCnt < 2 Then
       begin
	      Select b.child_pidm_2, b.child_name_2, a.gender
		  INTO locChld2Pidm, locChld2Name, locChld2Gender 
		  From bn.rtfiles a, adw.bio b
		  Where b.bio_pidm = locPidm(i) and b.child_pidm_2 = a.pidm and
		        a.cur_term = 'Y';
		  EXCEPTION
		     WHEN NO_DATA_FOUND THEN
			     locChld2Pidm := '';
				 locChld2Name := '';
				 locChld2Gender := '';
	   end;       
	      if insrtCnt = 0 Then
	      begin
		    UPDATE adw.ack_letters 
            SET al_child1_pidm = locChld2Pidm, al_child1_name = locChld2Name,
		        al_child1_gender = locChld2Gender
	        WHERE al_pidm = locPidm(i);
		  end;
		  else
		   if insrtCnt = 1 Then
		   begin
		     UPDATE adw.ack_letters 
             SET al_child2_pidm = locChld2Pidm, al_child2_name = locChld2Name,
		         al_child2_gender = locChld2Gender
	         WHERE al_pidm = locPidm(i);
           end;
		   end if;										   
		  end if;
		  insrtCnt := insrtCnt + 1;
     End if;   
   end if;
   if locChld3CY >= currFY and locChld3CY <= currFY+3 THEN   
     If insrtCnt < 2 Then
       begin
	      Select b.child_pidm_3, b.child_name_3, a.gender
		  INTO locChld3Pidm, locChld3Name, locChld3Gender 
		  From bn.rtfiles a, adw.bio b
		  Where b.bio_pidm = locPidm(i) and b.child_pidm_3 = a.pidm and
		        a.cur_term = 'Y';
		  EXCEPTION
		     WHEN NO_DATA_FOUND THEN
			     locChld3Pidm := '';
				 locChld3Name := '';
				 locChld3Gender := '';
	   end;       
	      if insrtCnt = 0 Then
	      begin
		    UPDATE adw.ack_letters 
            SET al_child1_pidm = locChld3Pidm, al_child1_name = locChld3Name,
		        al_child1_gender = locChld3Gender
	        WHERE al_pidm = locPidm(i);
		  end;
		  else
		   if insrtCnt = 1 Then
		   begin
		     UPDATE adw.ack_letters 
             SET al_child2_pidm = locChld3Pidm, al_child2_name = locChld3Name,
		         al_child2_gender = locChld3Gender
	         WHERE al_pidm = locPidm(i);
           end;
		   end if;										   
		  end if;
		  insrtCnt := insrtCnt + 1;
     End if;
   end if;
   if locChld4CY >= currFY and locChld4CY <= currFY+3 THEN   
     If insrtCnt < 2 Then
       begin
	      Select b.child_pidm_4, b.child_name_4, a.gender
		  INTO locChld4Pidm, locChld4Name, locChld4Gender 
		  From bn.rtfiles a, adw.bio b
		  Where b.bio_pidm = locPidm(i) and b.child_pidm_4 = a.pidm and
		        a.cur_term = 'Y';
		  EXCEPTION
		     WHEN NO_DATA_FOUND THEN
			     locChld4Pidm := '';
				 locChld4Name := '';
				 locChld4Gender := '';
	   end;       
	      if insrtCnt = 0 Then
	      begin
		    UPDATE adw.ack_letters 
            SET al_child1_pidm = locChld4Pidm, al_child1_name = locChld4Name,
		        al_child1_gender = locChld4Gender
	        WHERE al_pidm = locPidm(i);
		  end;
		  else
		   if insrtCnt = 1 Then
		   begin
		     UPDATE adw.ack_letters 
             SET al_child2_pidm = locChld4Pidm, al_child2_name = locChld4Name,
		         al_child2_gender = locChld4Gender
	         WHERE al_pidm = locPidm(i);
           end;
		   end if;										   
		  end if;
		  insrtCnt := insrtCnt + 1;
     End if;	 
	end if;
	    	 
  insrtCnt := 0; -- ReSet  
  END LOOP;
  commit;

END IF;

END updateChildData;

PROCEDURE backFillData
AS
BEGIN

updateOtherXrefData;
UPDATE adw.ack_letters
SET al_xref_from_to = null 
WHERE substr(al_xref_from_to,1,3) = 'DOD';
-------
UPDATE adw.ack_letters
SET al_id = (Select a.id From adw.shared a Where a.shared_pidm = al_pidm);
UPDATE adw.ack_letters
SET al_gender = (Select a.gender From adw.bio a Where a.bio_pidm(+) = al_pidm);
UPDATE adw.ack_letters
SET al_xref_id = (Select a.id From adw.shared a Where a.shared_pidm = al_xref_pidm);
-------
UPDATE adw.ack_letters a
SET a.al_pref_formal_street_1 = 
      (Select z.pref_street_line_1 From adw.address z Where z.addr_pidm = a.al_pidm),
    a.al_pref_formal_street_2 = 
      (Select z.pref_street_line_2 From adw.address z Where z.addr_pidm = a.al_pidm),
    a.al_pref_formal_street_3 = 
      (Select z.pref_street_line_3 From adw.address z Where z.addr_pidm = a.al_pidm),
	a.al_pref_formal_city = 
      (Select z.pref_city From adw.address z Where z.addr_pidm = a.al_pidm),
	a.al_pref_formal_state = 
      (Select z.pref_state From adw.address z Where z.addr_pidm = a.al_pidm),
	a.al_pref_formal_zip = 
      (Select z.pref_zip From adw.address z Where z.addr_pidm = a.al_pidm),
	a.al_pref_formal_nation = 
      (Select z.pref_nation From adw.address z Where z.addr_pidm = a.al_pidm);
--------
UPDATE adw.ack_letters
SET al_const_code = (Select b.const_codes From adw.shared b Where b.shared_pidm = al_pidm);

UPDATE adw.ack_letters a
SET al_firstTimeGift_Ind = 'Y' WHERE al_letr_code = '01';

--
UPDATE adw.ack_letters
SET al_class_yr = '1945-4'
WHERE al_class_yr = '4544';

UPDATE adw.ack_letters
SET al_reunion_yr = (currFY-al_class_yr)||'th'
WHERE al_letr_code in ('01L','01LA','01PL-R','02CPL-LR','02CPL-R','02L','02LA')
          and al_class_yr != '1945-4';

Update adw.ack_letters a
Set al_reunion_yr = '5th' Where al_reunion_yr in ('3th','4th');               
Update adw.ack_letters a
Set al_reunion_yr = '10th' Where al_reunion_yr in ('8th','9th');
Update adw.ack_letters a
Set al_reunion_yr = '15th' Where al_reunion_yr in ('13th','14th');
Update adw.ack_letters a
Set al_reunion_yr = '20th' Where al_reunion_yr in ('18th','19th');
Update adw.ack_letters a
Set al_reunion_yr = '25th' Where al_reunion_yr in ('23th','24th');
Update adw.ack_letters a
Set al_reunion_yr = '30th' Where al_reunion_yr in ('28th','29th');
Update adw.ack_letters a
Set al_reunion_yr = '35th' Where al_reunion_yr in ('33th','34th');
Update adw.ack_letters a
Set al_reunion_yr = '40th' Where al_reunion_yr in ('38th','39th');
Update adw.ack_letters a
Set al_reunion_yr = '45th' Where al_reunion_yr in ('43th','44th');
Update adw.ack_letters a
Set al_reunion_yr = '50th' Where al_reunion_yr in ('48th','49th');
Update adw.ack_letters a
Set al_reunion_yr = '55th' Where al_reunion_yr in ('53th','54th');	
Update adw.ack_letters a
Set al_reunion_yr = '60th' Where al_reunion_yr in ('58th','59th');
Update adw.ack_letters a
Set al_reunion_yr = '65th' Where al_reunion_yr in ('63th','64th');
Update adw.ack_letters a
Set al_reunion_yr = '70th' Where al_reunion_yr in ('68th','69th');
Update adw.ack_letters a
Set al_reunion_yr = '75th' Where al_reunion_yr in ('73th','74th');
Update adw.ack_letters a
Set al_reunion_yr = '80th' Where al_reunion_yr in ('78th','79th');

updateChildData;

UPDATE adw.ack_letters a
SET a.al_amt_pldg = 
(
Select distinct decode(sum(z.amt_pldg),0,null,sum(z.amt_pldg)) From adw.pledges z
Where z.pldg_num = a.al_pldg_num and z.pldg_pidm = a.al_pidm GROUP BY z.pldg_pidm
)
WHERE a.al_amt_pldg is null;
commit;

UPDATE adw.ack_letters a
SET a.al_pldg_open_bal = 
    (Select SUM(DISTINCT(decode(z.amt_open_bal,0,null,z.amt_open_bal))) from adw.giftpldg z
     Where z.pldg_num = a.al_pldg_num and z.gp_pidm = a.al_pidm and z.pldg_ind = 'Y' and
           z.desg = a.al_desg and z.gift_num is null
                                                 )
WHERE a.al_pldg_open_bal is null;

UPDATE adw.ack_letters a
SET a.al_giving_vehicle = 
       (Select distinct z.giving_vehicle From adw.giftpldg z
        Where z.gift_num = a.al_gift_num and z.gp_pidm = a.al_pidm and
	          trim(a.al_gift_num) is not null and z.giving_vehicle is not null and
	   		  trim(z.mg_xref_pidm) is null)
WHERE al_giving_vehicle is null;

UPDATE adw.ack_letters a
SET a.al_giving_vehicle = (Select distinct z.giving_vehicle From adw.giftpldg z
                           Where z.pldg_num = a.al_pldg_num and z.gp_pidm = a.al_pidm and
						         trim(a.al_gift_num) is null and trim(z.gift_num) is null and
								 z.giving_vehicle is not null and z.giving_vehicle != 'PLEDGE')
WHERE al_giving_vehicle is null;

UPDATE adw.ack_letters a
SET a.al_giving_vehicle = (Select distinct z.giving_vehicle From adw.giftpldg z
                           Where z.pldg_num = a.al_pldg_num and z.gp_pidm = a.al_pidm and
						         trim(a.al_gift_num) is null and
								 z.giving_vehicle = 'PLEDGE')
WHERE al_giving_vehicle is null;

UPDATE adw.ack_letters a 
SET a.al_gift_act_date = 
         (Select Distinct to_date(to_char(z.gp_act_date,'DD-MON-YYYY'),'DD-MON-YYYY')
          From adw.giftpldg z
		  Where z.gp_pidm = a.al_pidm and z.gift_num = a.al_gift_num and
                a.AL_GIVING_VEHICLE = z.GIVING_VEHICLE                           
         )
Where a.al_gift_act_date is null;

UPDATE adw.ack_letters a 
SET a.al_gift_act_date = 
       (Select Distinct to_date(to_char(z.gp_act_date,'DD-MON-YYYY'),'DD-MON-YYYY')
        From adw.giftpldg z
	    Where z.gp_pidm = a.al_pidm and
              a.AL_GIVING_VEHICLE = z.GIVING_VEHICLE and
	          z.pldg_num = a.al_pldg_num and 
              a.al_gift_num is null and z.gift_num is null
       )
Where a.al_gift_act_date is null;

UPDATE adw.ack_letters a 
SET a.al_orig_pldg_date = 
     (Select Distinct to_date(to_char(z.agbpldg_pledge_date,'DD-MON-YYYY'),'DD-MON-YYYY')
      From alumni.agbpldg z
	  Where z.agbpldg_pledge_no = a.al_pldg_num and a.al_pldg_num is not null)
Where a.al_orig_pldg_date is null and trim(a.al_pldg_num) is not null;

UPDATE adw.ack_letters a 
SET a.al_gift_tax_date = 
       (Select Distinct to_date(to_char(z.gp_date,'DD-MON-YYYY'),'DD-MON-YYYY')
        From adw.giftpldg z
        Where z.gp_pidm = a.al_pidm and z.gift_num = a.al_gift_num and
              a.AL_GIVING_VEHICLE = z.GIVING_VEHICLE
       )
Where a.al_gift_tax_date is null;

UPDATE adw.ack_letters a 
SET a.al_gift_tax_date = 
       (Select Distinct to_date(to_char(z.gp_date,'DD-MON-YYYY'),'DD-MON-YYYY')
        From adw.giftpldg z
	    Where z.gp_pidm = a.al_pidm and
	          z.pldg_num = a.al_pldg_num and a.al_gift_num is null and
              a.al_giving_vehicle = z.giving_vehicle and
              z.gift_num is null)
Where a.al_gift_tax_date is null;

UPDATE adw.ack_letters a
SET a.al_agrgaux_desc = (Select Distinct z.AGRGAUX_DESC          
                         From adw.giftpldg z
                         Where z.gp_pidm = a.al_pidm and z.gift_num = a.al_gift_num and
                               a.AL_PLDG_NUM = z.PLDG_NUM and
                               z.agrgaux_desc is not null)
Where a.al_agrgaux_desc is null;

UPDATE adw.ack_letters a
SET a.al_agrgaux_desc = (Select Distinct z.AGRGAUX_DESC          
                         From adw.giftpldg z
						 Where z.gp_pidm = a.al_pidm and z.pldg_num = a.al_pldg_num and 
                               a.al_gift_num is null and z.gift_num is null and
						       z.agrgaux_desc is not null)
Where a.al_agrgaux_desc is null;
 
-- Split Ind 
UPDATE adw.ack_letters a
SET a.al_split_ind = 'Y' 
WHERE a.al_split_ind is null and
	  a.al_gift_comt IN ('SPAN','SPHM','SANO','SPIB','SPLT','SPMH','SPMN',
                         'SPNH','SPNM','SPNO');
commit;
UPDATE adw.ack_letters a
SET a.al_split_ind = 'Y'
WHERE a.al_split_ind is null and a.al_pidm in (Select z.gp_pidm From adw.giftpldg z
                                               Where z.gp_pidm = a.al_pidm and z.gift_num = 
                                                     a.al_gift_num and z.split_ind = 'Y')
;
UPDATE adw.ack_letters a
SET a.al_split_ind = 'Y'
WHERE a.al_split_ind is null and a.al_pidm in (Select z.gp_pidm From adw.giftpldg z
                                               Where z.gp_pidm = a.al_pidm and z.pldg_num = 
                                                     a.al_pldg_num and z.split_ind = 'Y')
and a.al_gift_num is null
;


UPDATE adw.ack_letters a
SET a.al_joint_ind = 'Y' 
WHERE a.al_joint_ind is null and a.al_gift_comt IN ('JAN','JANO','JNOR','JOIN','NIHJ','NIMJ');

commit;

-- Use JointName where appl..   
UPDATE adw.ack_letters a
SET a.al_name_list = (Select b.name_joint_mail 
                      From adw.bio b
		   	          Where b.bio_pidm = a.al_pidm)
WHERE (a.al_split_ind = 'Y' OR a.al_joint_ind = 'Y' OR a.AL_LETR_CODE like '04P%' );

UPDATE adw.ack_letters a
SET a.al_comp_pldg = 'Y' 
Where (a.al_letr_desc like 'Completion of Pledge/%' or
       a.al_letr_desc like 'Completion of Pledge%');
      
-- UAL Completion of Pledges    
UPDATE adw.ack_letters a 
SET a.al_comp_pldg = 'Y' 
WHERE a.al_letr_code = 'UAL' and Trim(a.al_gift_num) is not null and
      Trim(a.al_pldg_num) is not null and
      Trim(a.al_pldg_num) = (Select Distinct b.pldg_num From adw.giftpldg b
	                         Where b.pldg_num = a.al_pldg_num and
                                   b.xref_pidm is null and 
                                   b.pldg_status = 'P' and
    					           b.AMT_OPEN_BAL = 0);

commit;
END backFillData;

PROCEDURE cleanUpGifts
AS
BEGIN

swapDesgDescs;

UPDATE adw.ack_letters
SET al_letr_desc = trim(al_letr_desc || substr(al_comment,5,50))
WHERE al_letr_code in ('01AF','02AF','03AF','04AF') 
      and al_wom is null and al_activity_date like sysdate;
UPDATE adw.ack_letters
SET al_letr_desc = trim(al_letr_desc || 'Once More to ' || substr(al_comment,5,50))
WHERE al_letr_code in ('01AF','02AF','03AF','04AF') 
      and al_wom is not null and al_activity_date like sysdate;
      
UPDATE adw.ack_letters
SET al_letr_desc = trim(al_letr_desc || 'Welcome to ' || substr(al_comment,5,50))
WHERE al_letr_code in ('02CPL','02CPL-T', '04FRND.2','04PALM.2','04PRNT.2')
      and al_comp_pldg = 'Y' and al_activity_date like sysdate;
      
UPDATE adw.ack_letters
SET al_pldg_num = '' WHERE al_pldg_num = '0000000';

Delete from adw.ack_letters
Where al_const_code like '%MTCH%' and al_giving_vehicle != 'TMCH';

UPDATE adw.ack_letters
SET al_letr_code = 'UAL', al_letr_desc = null, al_comment = null
Where al_const_code like '%TRUS%' or al_const_code like '%FTRS%';
    
UPDATE adw.ack_letters
SET al_letr_code = 'UAL', al_letr_desc = null, al_comment = null
Where al_pidm in (select b.apvacty_pidm from apvacty b where b.apvacty_pidm = al_pidm and
                         b.apvacty_actc_code in ('PAC','CAMPSTR','CAMPLDR','PIAC'));

UPDATE adw.ack_letters a
SET a.al_letr_code = 'UAL', a.al_letr_desc = null, a.al_comment = null
Where a.al_xref_pidm in (select b.shared_pidm
                         from adw.shared b
                         where b.shared_pidm = a.al_xref_pidm and
                               b.const_codes like '%TRST%'); 

UPDATE adw.ack_letters a
SET a.al_letr_code = 'UAL', a.al_letr_desc = null, a.al_comment = null
Where a.al_pidm in (select b.pros_pidm
                    from adw.prospects b
                    where b.pros_pidm = a.al_pidm and
                          b.pros_rate_code_p in ('01','00')); 
	      
UPDATE adw.ack_letters a
SET a.al_gift_entry_date = 
     (Select Distinct to_date(to_char(b.gp_entry_date,'DD-MON-YYYY'),'DD-MON-YYYY')
      From adw.giftpldg b
	  Where a.al_gift_num = b.gift_num and
	        b.AGRGAUX_DESC like 'STOCK%' and (b.gift_ind = 'Y' or pldg_pay_ind = 'Y')
	 )
Where a.al_gift_num in (Select c.gift_num From adw.giftpldg c
                       Where c.AGRGAUX_DESC like 'STOCK%' and
					         c.gift_num = a.al_gift_num
					  );	

UPDATE adw.ack_letters a
SET al_letr_code = 'UAL', al_letr_desc = null, al_comment = null
WHERE a.al_const_code like '%STUD%';

UPDATE adw.ack_letters
SET al_class_yr = '9999'
WHERE al_class_yr is null;

UPDATE adw.ack_letters
SET al_letr_code = 'UAL', al_letr_desc = null, al_comment = null
Where al_pidm||al_gift_num in
(
select a.al_pidm||a.al_gift_num PG_ConCat
from adw.ack_letters a, adw.ack_letters b
where a.al_xref_pidm = b.al_xref_pidm and 
      a.al_pref_formal_street_1 = b.al_pref_formal_street_1 and
      a.al_pref_formal_zip = b.al_pref_formal_zip and
      a.al_pidm != b.al_pidm and a.al_gift_num = b.al_gift_num
);

-- Fix 'the' to 'The' for Mag. Enter. soc..
UPDATE adw.ack_letters
SET al_comment = 'The '||SubStr(al_comment,5,99) 
Where SubStr(al_comment,5,6) = 'Magnif';

-- TEMP: this updates letters for Trustee Incentive...   
UPDATE adw.ack_letters
SET al_letr_code = '02CPL-T' 
WHERE al_letr_code = '02CPL' and al_class_yr between '1987' and '2005' and
      al_orig_pldg_date between 
           to_date('01-JUL-2005','DD-MON-YYYY') and to_date('30-JUN-2006','DD-MON-YYYY');

commit;

-- Pledge/Pledge First Payment (Comp. of Pledge) only gets one row each donor..   
delete from adw.ack_letters a
where a.AL_PLDG_NUM in (Select b.al_pldg_num From adw.ack_letters b where 
                        a.al_pldg_num = b.al_pldg_num and
                        b.AL_GIFT_NUM is not null and b.al_letr_code in ('01PL','01PL-R') 
                        and b.al_letr_desc in ('Pledge and First Payment to Vassar Fund',
                                               'Pledge and First Payment to Class Reunion'
                                              )
                        and b.al_activity_date like sysdate
                       )
      and (a.al_gift_num is null OR a.al_letr_desc not in 
                                                ('Pledge and First Payment to Vassar Fund',
                                                 'Pledge and First Payment to Class Reunion'
                                                ) 
          )
      and al_activity_date like sysdate;

delete from adw.ack_letters a
where a.AL_PLDG_NUM in (Select b.al_pldg_num From adw.ack_letters b where 
                        a.al_pldg_num = b.al_pldg_num and
                        b.AL_GIFT_NUM is not null 
                        and b.al_letr_desc like 'Completion of Pledge%'
                        and b.al_activity_date like sysdate)
      and (a.al_gift_num is null OR a.al_letr_desc not like 'Completion of Pledge%') 
      and al_activity_date like sysdate;
      
commit;

END cleanUpGifts;

PROCEDURE insertAckLetter(indexIn in number, letrIn in varchar2, descIn in varchar, 
                          socIn in varchar2, womIn in varchar2, matchText in varchar2)
AS

BEGIN
insert into adw.ack_letters(al_pidm, al_class_yr, al_name_list, al_desg, al_gift_num, al_pldg_num, 
                                  al_amt, al_xref_from_to, al_fisc_yr, al_gift_entry_date, 
                                  al_camp, al_gift_comt, al_xref_pidm,
                                  al_letr_code, al_letr_desc, al_comment, al_wom, al_mg_comment, 
                                  al_activity_date,AL_RCNT_EVNT_IND, al_pldg_status)
values(workingPidm, workingCY, tName, allGPData(indexIn).desg, allGPData(indexIn).giftNum, 
       allGPData(indexIn).pldgNum, allGPData(indexIn).amtDesg, globalOBOName, 
       allGPData(indexIn).fy, allGPData(indexIn).entryDate, allGPData(indexIn).camp,
       allGPData(indexIn).clsCode, workingXrefPidm,
       letrIn, descIn, socIn, womIn, matchText, sysdate,recentEvntInd, allGPData(indexIn).pldg_status );

commit;

END insertAckLetter;

PROCEDURE pPldgController(indexIn in number, letrIn in varchar2, descIn in varchar2,
                          prevAmtsIn in number) /* The Society */   
AS
locPrevAmts      NUMBER;
totalToConsider  NUMBER;
thisGiftAmt      NUMBER;
locLastFYAmts    NUMBER;
locWaitMatch     NUMBER;
FYGiftNumCycle   NUMBER;
locMatchText     adw.ack_letters.al_mg_comment%type;
finalLetrCode    adw.ack_letters.AL_LETR_CODE%TYPE := '';
finalLetrDesc    adw.ack_letters.AL_LETR_DESC%TYPE := '';
locSoc           adw.ack_letters.AL_LETR_DESC%TYPE := '';
locSocPREV       adw.ack_letters.AL_LETR_DESC%TYPE := '';
locSocLastFY     adw.ack_letters.AL_LETR_DESC%TYPE := ''; 
WOMFlag          varchar2(1) := '';
stockChk         VARCHAR(1) := 'N';

BEGIN

-- XREF amt fix ------>   
if allGPData(indexIn).afAmtTotal is not null and allGPData(indexIn).xrefCredit is not null THEN
  allGPData(indexIn).afAmtTotal := allGPdata(indexIn).xrefCredit;
end if; 

stockChk := chkIfStock(allGPData(indexIn).giftNum);
if stockChk = 'Y' Then 
  allGPData(indexIn).afAmtTotal := (allGPData(indexIn).afAmtTotal + 50); 
  stockChk := 'N';
end if;
  
locWaitMatch := WaitMatchChk(workingPidm, workingXrefPidm, allGPData(indexIn).giftnum);     
if locWaitMatch > 0 then locMatchText := 'With a Waiting Match'; end if;

-- ########################################################### --
totalToConsider := prevAmtsIn + allGPData(indexIn).afAmtTotal + locWaitMatch;

locLastFYAmts := PrevFYChk(workingPidm, (currFY-1));
locSoc := findGiftSociety(totalToConsider);
locSocPREV := findGiftSociety(PrevAmtsIn);
locSocLastFY := findGiftSociety(locLastFYAmts);


--------- Testing ---------------
/*dbms_output.put_line('Af Total: ' || allGPData(indexIn).afAmtTotal);
dbms_output.put_line('Wait Match: ' || locWaitMatch);
dbms_output.put_line('Curr Prev Amts: ' || currPrevAmts);
dbms_output.put_line('Curr Prev Amts 3yr: ' || currPrevAmts3YR);
dbms_output.put_line('totalToConsider: ' || totalToConsider);
*/
----------------------------------

-- ########################################################### -- 
  
if ((isOneToFiveOut and totalToConsider >= min15) 
    OR (isSixToTenOut and totalToConsider >= min610)
    OR (totalToConsider >= minOver10)
    OR (isMostRecentGrad)
   )
   AND (locSoc != locSocPREV OR 
        allGPData(indexIn).afAmtTotal >= minOver10 OR 
        isCompPldg OR 
        isPldgAndFirstPay)
THEN

   if locSoc = locSocLastFY Then    
	    WOMFlag := 'Y';
   end if;
   if (isMostRecentGrad) then
     if (isCompPldg) Then
       finalLetrCode := '05A'; 
       finalLetrDesc := 'Completion of Pledge from Member of Recent Graduating Class';
       locSoc := '';
     else
       finalLetrCode := '05A'; 
       finalLetrDesc := 'Pledge from Member of Recent Graduating Class';
       locSoc := '';
     end if;
   else
     if (allGPData(indexIn).amtTotal >= 50000) then
       finalLetrCode := 'UAL';
       finalLetrDesc := '';
       locSoc := '';
     else
       finalLetrCode := letrIn;
       finalLetrDesc := descIn;
      locSoc := 'the '||locSoc;
       
     end if;
   end if;  
   
   insertAckLetter(indexIn, finalLetrCode, finalLetrDesc, locSoc, WOMFlag, locMatchText);
   notAssigned := false; 		 
end if;

END pPldgController;

PROCEDURE pGiftController(indexIn in number, letrIn in varchar2, descIn in varchar2,
                          prevAmtsIn in number) /* The Society */    
AS
locPrevAmts      NUMBER;
totalToConsider  NUMBER;
thisGiftAmt      NUMBER;
locLastFYAmts    NUMBER;
locWaitMatch     NUMBER;
locMatchText     adw.ack_letters.al_mg_comment%type;
FYGiftNumCycle   NUMBER;
finalLetrCode    adw.ack_letters.AL_LETR_CODE%TYPE := '';
finalLetrDesc    adw.ack_letters.AL_LETR_DESC%TYPE := '';
locSoc           adw.ack_letters.AL_LETR_DESC%TYPE := '';
locSocPREV       adw.ack_letters.AL_LETR_DESC%TYPE := '';
locSocLastFY     adw.ack_letters.AL_LETR_DESC%TYPE := ''; 
WOMFlag          varchar2(1) := '';
stockChk         VARCHAR(1) := 'N';

BEGIN

-- XREF amt fix ------>   
if allGPData(indexIn).afAmtTotal is not null and 
   allGPData(indexIn).xrefCredit is not null and
   allGPData(indexIn).xrefClassYr != '0000'
THEN
  allGPData(indexIn).afAmtTotal := allGPdata(indexIn).xrefCredit;
end if;  

stockChk := chkIfStock(allGPData(indexIn).giftNum);
if stockChk = 'Y' Then 
  allGPData(indexIn).afAmtTotal := (allGPData(indexIn).afAmtTotal + 50); 
  stockChk := 'N';
end if;

locWaitMatch := WaitMatchChk(workingPidm, workingXrefPidm, allGPData(indexIn).giftnum);     
if locWaitMatch > 0 then locMatchText := 'With a Waiting Match'; end if;

-- ################################################################ --
totalToConsider := prevAmtsIn + allGPData(indexIn).afAmtTotal + locWaitMatch;

locLastFYAmts := PrevFYChk(workingPidm, (currFY-1));
locSoc := findGiftSociety(totalToConsider);
locSocPREV := findGiftSociety(PrevAmtsIn);
locSocLastFY := findGiftSociety(locLastFYAmts);
-- ################################################################ -- 

/* TESTING STUFF 
dbms_output.put_line('locWaitMatch '|| locWaitMatch);
dbms_output.put_line('prevAmtsIn '|| prevAmtsIn);
dbms_output.put_line('locSoc '|| locSoc);
dbms_output.put_line('locSocPREV '|| locSocPREV);
dbms_output.put_line('afAmtTotal ' || allGPData(indexIn).afAmtTotal);
dbms_output.put_line('totalToConsider '|| totalToConsider); 
*/   

if (
       (isOneToFiveOut and totalToConsider >= min15) 
    OR (isSixToTenOut and totalToConsider >= min610)
    OR (totalToConsider >= minOver10)
    OR (isMostRecentGrad)
   )
   AND (locSoc != locSocPREV OR 
        locSocPREV is null OR 
        allGPData(indexIn).afAmtTotal >= minOver10 )
THEN
 
   if locSoc = locSocLastFY Then    
       WOMFlag := 'Y';
   end if;
   if (isMostRecentGrad) then
     finalLetrCode := '05'; 
     finalLetrDesc := 'Gift from Member of Recent Graduating Class';
     locSoc := '';
   else
     finalLetrCode := letrIn;
     finalLetrDesc := descIn;
     locSoc := 'the '||locSoc;
    
   end if;  
   insertAckLetter(indexIn, finalLetrCode, finalLetrDesc, locSoc, WOMFlag, locMatchText);
   notAssigned := false; 		 
end if;

END pGiftController;

PROCEDURE tryAssignGift(indexIn in number) /* The Letter */     
AS
letrCodeToPassLR  adw.ack_letters.al_letr_code%TYPE := '';
letrCodeToPassR   adw.ack_letters.al_letr_code%TYPE := '';
letrCodeToPass    adw.ack_letters.al_letr_code%TYPE := '';
letrDescToPassLR  adw.ack_letters.al_letr_desc%TYPE := '';
letrDescToPassR   adw.ack_letters.al_letr_desc%TYPE := '';
letrDescToPass    adw.ack_letters.al_letr_desc%TYPE := '';
locCycleCnt       number;
BEGIN

if (allGPData(indexIn).camp like 'EXS%') then
   if (allGPData(indexIn).desg like 'BX%') then
      pGiftController(indexIn, '16', 'Posse Gift', currPrevAmts);
   else
      pGiftController(indexIn, '15', 'Expendable Scholarships', currPrevAmts);
   end if;
else
------------- Number of Gifts this year ------------>  
locCycleCnt := chkGiftNumCycle(workingPidm, allGPData(indexIn).entryDate);

if locCycleCnt > 1 then    
  letrCodeToPassLR := '02LA'; 
  letrDescToPassLR := 'Additional Gift to Landmark Reunion';
  letrCodeToPassR := '02L'; 
  letrDescToPassR := 'Additional Gift to Class Reunion';
  case 
   when locCycleCnt = 2 then letrCodeToPass := '02AF'; letrDescToPass := 'Second/Additional Gift - ';
   when locCycleCnt = 3 then letrCodeToPass := '03AF'; letrDescToPass := 'Third Gift - ';
   when locCycleCnt >= 4 then letrCodeToPass := '04AF'; letrDescToPass := 'Fourth Gift - ';
  end case;
else 
  letrCodeToPassLR := '01LA';  
  letrDescToPassLR := 'Gift to Landmark Reunion';
  letrCodeToPassR := '01L';
  letrDescToPassR := 'Gift to Class Reunion';
  letrCodeToPass := '01AF';
  letrDescToPass := '';
end if;

  
---------------------------------------------------->         
if allGPData(indexIn).desg in ('AFALM','AFFAC','AFATH','AFCAM','AFLIB','AFRES',
                                   'AFSCH','AFPAF','AFSUS','AFFACVF','AFATHVF','AFCAMVF','AFLIBVF','AFRESVF','AFSCHVF', 'AFALMVF','AFPAFVF','AFSUSVF') THEN
 if (currLRYear) then
  pGiftController(indexIn, letrCodeToPassLR, letrDescToPassLR, currPrevAmts3YR);
 end if;
 if (currRYear) then
  pGiftController(indexIn, letrCodeToPassR, letrDescToPassR, currPrevAmts);
 end if;
 if not(currLRYear) AND not(currRYear) THEN
   if (currDonorCode like '%ALUM%' or currDonorCode like '%ALND%') then
    pGiftController(indexIn, letrCodeToPass, letrDescToPass, currPrevAmts);
   else 
   if currDonorCode like '%PALM%' then 
    if locCycleCnt > 1 then 
         letrCodeToPass := '04PALM.2'; 
         letrDescToPass := 'Addition Gift to Parents (no current student)';
    else letrCodeToPass := '04PALM'; 
         letrDescToPass := 'Gift to Parents (no current student)'; 
    end if;
    pGiftController(indexIn, letrCodeToPass, letrDescToPass, currPrevAmts);
   else
   if currDonorCode like '%PRNT%' then
    if locCycleCnt > 1 then 
         letrCodeToPass := '04PRNT.2'; 
         letrDescToPass := 'Addition Gift to Parents (current student)';
    else letrCodeToPass := '04PRNT'; 
         letrDescToPass := 'Gift to Parents (current student)'; 
    end if;
    pGiftController(indexIn, letrCodeToPass, letrDescToPass, currPrevAmts);
   else
   if currDonorCode like '%FRND%' then
    if locCycleCnt > 1 then 
         letrCodeToPass := '04FRND.2'; 
         letrDescToPass := 'Addition Gift to Patrons Fund';
    else letrCodeToPass := '04FRND'; 
         letrDescToPass := 'Gift to Patrons Fund'; 
    end if;
    pGiftController(indexIn, letrCodeToPass, letrDescToPass, currPrevAmts);
   end if;
   end if;
   end if;
   end if;
 end if;
end if;

end if; -- VF check 


if notAssigned AND ((allGPData(indexIn).amtTotal >= minOver10) OR 
                     (allGPData(indexIn).amtTotal >= min610 and 
                      isSixToTenOut) OR 
                     (allGPData(indexIn).amtTotal >= min15 and
                      isOneToFiveOut)
                    ) THEN
    insertAckLetter(indexIn, 'UAL','','','','');
    notAssigned := false;                                               
end if;
if notAssigned AND allGPData(indexIn).giftCode in ('GK','GN') THEN /* Gift In Kind */    
    insertAckLetter(indexIn,'UAL','','','','');
    notAssigned := false;
end if;
if notAssigned AND allGPData(indexIn).giftCode like 'B%' THEN /* Bequest */    
    insertAckLetter(indexIn,'UAL','','','','');
    notAssigned := false;
end if;
if notAssigned AND allGPData(indexIn).desg like 'SV%' 
             and (allGPData(indexIn).classYr = '9999' or allGPData(indexIn).classYr is null)
THEN /* Club Gift/Pldg */    
    insertAckLetter(indexIn,'UAL','','','','');
    notAssigned := false;
end if;
if notAssigned AND isFirstEverGift THEN
    insertAckLetter(indexIn,'01','First Time Gift', '','','');
    notAssigned := false;
end if;
if notAssigned AND workingCC like '%TRUS%' THEN
    insertAckLetter(indexIn,'UAL','', '','','');
    notAssigned := false;
end if;

END tryAssignGift;

PROCEDURE tryAssignPledgeOrPayment(indexIn in number) /* The Letter */
AS
BEGIN

if (allGPData(indexIn).camp like 'EXS%') then
   if (allGPData(indexIn).desg like 'BX%') then
      pGiftController(indexIn, '16', 'Posse Gift', currPrevAmts);
   else
      pGiftController(indexIn, '15', 'Expendable Scholarships', currPrevAmts);
   end if;
else

----------------------------------------------------------

if (isPldgAndFirstPay) and not(isCompPldg) then -- Pldg And First Payment   
  if (currRYear) then
  pPldgController(indexIn, '01PL-R','Pledge and First Payment to Class Reunion', currPrevAmts); 
  else
   if (currLRYear) then
   pPldgController(indexIn, '01PL-R','Pledge and First Payment to Class Reunion', currPrevAmts);
   else
    if currDonorCode like '%ALUM%' or currDonorCode like '%ALND%' then
    pPldgController(indexIn, '01PL','Pledge and First Payment to Vassar Fund', currPrevAmts);
    else 
     if currDonorCode like '%PALM%' then 
     pPldgController(indexIn, '04PALM', 'Pledge to Parents (no current student)', currPrevAmts);
     else
      if currDonorCode like '%PRNT%' then
      pPldgController(indexIn, '04PRNT', 'Pledge to Parents (current student)', currPrevAmts);
      else
       if currDonorCode like '%FRND%' then
       pPldgController(indexIn, '04FRND','Pledge to Patrons Fund', currPrevAmts);
       end if;
      end if;
     end if;
    end if;
   end if;
  end if;
end if; 

-------------------------------------------------------------> 
if (isCompPldg) then -- Completion of Pledge   
  if (currRYear) then
   pPldgController(indexIn, '02CPL-R','Completion of Pledge to Reunion Fund', currPrevAmts);
  else
  if (currLRYear) then
   pPldgController(indexIn, '02CPL-LR','Completion of Pledge to Landmark Reunion Fund', currPrevAmts3YR);
  else
  if currDonorCode like '%ALUM%' or currDonorCode like '%ALND%' then
   pPldgController(indexIn, '02CPL','Completion of Pledge/', currPrevAmts);
  else
  if currDonorCode like '%PALM%' then 
   pPldgController(indexIn, '04PALM.2','Completion of Pledge/', currPrevAmts);
  else
  if currDonorCode like '%PRNT%' then
   pPldgController(indexIn, '04PRNT.2','Completion of Pledge/', currPrevAmts);
  else
  if currDonorCode like '%FRND%' then
   pPldgController(indexIn, '04FRND.2','Completion of Pledge/', currPrevAmts);
  end if;
  end if;
  end if;
  end if;
  end if;
  end if;

end if;

----------------------------------------------------------------> 
if (isStraightPldg) then -- OutRight Pledge  
  if (currRYear) then
   pPldgController(indexIn, '01PL-R','Pledge to Class Reunion', currPrevAmts);
  else
  if (currLRYear) then
   pPldgController(indexIn, '01PL-R','Pledge to Class Reunion', currPrevAmts);
  else
  if currDonorCode like '%ALUM%' or currDonorCode like '%ALND%' then
   pPldgController(indexIn, '01PL','Pledge to Vassar Fund', currPrevAmts);
  else 
  if currDonorCode like '%PALM%' then 
   pPldgController(indexIn, '04PALM','Pledge to Parents (no current student)', currPrevAmts);
  else
  if currDonorCode like '%PRNT%' then
   pPldgController(indexIn, '04PRNT','Pledge to Parents (current student)', currPrevAmts);
  else
  if currDonorCode like '%FRND%' then
   pPldgController(indexIn, '04FRND','Pledge to Patron Fund', currPrevAmts);  
  end if;
  end if;
  end if;
  end if;
  end if;
  end if;
  
end if;

end if; --VF check   


if notAssigned AND (allGPData(indexIn).amtTotal >= 50000) THEN
    insertAckLetter(indexIn, 'UAL','','','','');                                               
    notAssigned := false;
end if;  
-- 02/2010 A.   
if notAssigned AND (isCompPldg or isPldgAndFirstPay or isStraightPldg) THEN
 if ((isOneToFiveOut and allGPData(indexIn).totAmtPldg >= min15) 
    OR (isSixToTenOut and allGPData(indexIn).totAmtPldg >= min610)
    OR (allGPData(indexIn).totAmtPldg >= minOver10)
   ) THEN
    insertAckLetter(indexIn, 'UAL','','','','');                                               
    notAssigned := false;
 end if;
end if;
if notAssigned AND allGPData(indexIn).giftCode in ('GK','GN') THEN /* Gift In Kind */ 
    insertAckLetter(indexIn,'UAL','','','','');
    notAssigned := false;
end if;
if notAssigned AND allGPData(indexIn).giftCode like 'B%' THEN /* Bequest */ 
    insertAckLetter(indexIn,'UAL','','','','');
    notAssigned := false;
end if;
if notAssigned AND allGPData(indexIn).desg like 'SV%' 
        and allGPData(indexIn).classYr = '9999' THEN /* Club Gifts/Pldg */ 
    insertAckLetter(indexIn,'UAL','','','','');
    notAssigned := false;
end if;
if notAssigned AND workingCC like '%TRUS%' THEN
    insertAckLetter(indexIn,'UAL','Trustee', '','','');
    notAssigned := false;
end if;

END tryAssignPledgeOrPayment;

PROCEDURE pStarter
AS
LdontAssign boolean := false;

BEGIN
currFY := adwgenl.GET_CURR_FISC_YR;


open c1;
fetch c1 BULK COLLECT INTO allGPData;
FOR i in allGPData.FIRST..allGPData.LAST
LOOP
---- xref check/swap ---------------------------------->  
-------------------------------------------------------> 
if allGPData(i).xrefpidm is not null THEN
    if(checkOBO(allGPData(i).pidm, allGPData(i).giftnum, allGPData(i).pldgnum, allGPData(i).xrefpidm)) then
      workingPidm := allGPData(i).xrefPidm;
      workingXRefPidm := allGPData(i).pidm;
      adwgenl.GET_NAME_AND_CLASS(allGPData(i).pidm, tName, tCY, tCYS, tGY);
      globalOBOName := 'OBO From: ' || tName;
      adwgenl.GET_NAME_AND_CLASS(allGPData(i).xrefPidm, tName, tCY, tCYS, tGY);
      workingCY := allGPData(i).xrefClassYr;
      workingCC := dConstCodes(workingPidm);
    else
      workingPidm := allGPData(i).pidm;
      adwgenl.GET_NAME_AND_CLASS(allGPData(i).pidm, tName, tCY, tCYS, tGY);
      workingXrefPidm := null;
      globalOBOName := '';
      workingCY := allGPData(i).classYr;
      workingCC := dConstCodes(workingPidm);
    end if;
else
   workingPidm := allGPData(i).pidm;
   adwgenl.GET_NAME_AND_CLASS(allGPData(i).pidm, tName, tCY, tCYS, tGY);
   workingXrefPidm := null;
   globalOBOName := '';
   workingCY := allGPData(i).classYr;
   workingCC := dConstCodes(workingPidm);
end if;    
------ Define some variables ----------------------------->  
----------------------------------------------------------> 
currDonorCode := getDonorCode(workingPidm);
currRYear := isReunion(workingCY);
currLRYear := isLandMarkReunion(workingCY);
isOneToFiveOut := chkOneFive(workingCY);
isSixToTenOut := chkSixTen(workingCY);
isMostRecentGrad := chkMostRecentGrad(workingCY);

-- Event Tracking (01/2010)  
/* remove (12/2010) handled in report 
recentEvntInd := getRecentEvnts(workingPidm);
*/

-------- Pldg / Pldg Payment Assigments --------------------> 
------------------------------------------------------------>   

if allGPData(i).pldgnum != '0000000' THEN
  if allGPData(i).giftnum is null then 
    isStraightPldg := true; 
  end if;
  isPldgAndFirstPay := chkPldgFirstPay(allGPData(i).pldgnum, i);
  isCompPldg := chkCompPldg(allGPData(i).pldgnum);
    if (isCompPldg) THEN /* recheck this as a 'reunion' type */  
      currRYear := isReunionCP(workingCY);
    end if;
  currPrevAmts := PrevChk(workingPidm, allGPData(i).entryDate, allGPData(i).pldgnum);
  currPrevAmts3YR := PrevChk3YR(workingPidm, allGPData(i).entryDate);
  
  /* Take care of Pledge + First Payment showing up twice */     
  if not(isStraightPldg) and (isPldgAndFirstPay) and not(isCompPldg) THEN
    LdontAssign := true;
  else  
    tryAssignPledgeOrPayment(i);
  end if;
else
-------- Straight Gift Asignments --------------------------->  
------------------------------------------------------------->  
  currPrevAmts := PrevChk(workingPidm, allGPData(i).entryDate,'999');
  currPrevAmts3YR := PrevChk3YR(workingPidm, allGPData(i).entryDate);
  isFirstEverGift := chkIfFirst(workingPidm, allGPData(i).giftNum);
  tryAssignGift(i);
end if;

isStraightPldg := false;  
notAssigned := true;
END LOOP;

--------- Clean-Up ; Back - Fill ----------------------------->  
--------------------------------------------------------------> 

/* testing (comment this..) */     
backFillData;
cleanUpGifts;
/* ---------------   */   


END pStarter;

END drLetrAssignment;