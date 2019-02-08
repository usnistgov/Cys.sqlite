/* calculate average DSE for X-Ray <= 1.5 with occ<1/alt_id */
SELECT  avg(cys_cys.dse), count (cys_cys.dse)
FROM    PDB pdb
        JOIN CYS_CYS cys_cys
            ON pdb.id = cys_cys.pdb_id
WHERE   pdb.exp_method = 'X-RAY DIFFRACTION'
  AND   pdb.resolution <= 1.5
  AND   pdb.status = 'CURRENT'
  AND   cys_cys.alt_occ_flag IS NOT NULL

/* calculate average DSE for X-Ray <= 1.2 with full occupancy */
SELECT  avg(cys_cys.dse), count (cys_cys.dse)
FROM    PDB pdb
        JOIN CYS_CYS cys_cys
            ON pdb.id = cys_cys.pdb_id
WHERE   pdb.exp_method = 'X-RAY DIFFRACTION'
  AND   pdb.resolution <= 1.2
  AND   pdb.status = 'CURRENT'
  AND   cys_cys.alt_occ_flag IS NULL


/* 
   distinct entity_cys entries from the CYS_CYS table ordered by disulfide 
   based on entity_idi
*/ 

SELECT entity_idi, count(id), count(distinct pdb_id) 
FROM CYS_CYS 
   GROUP BY entity_idi 
   ORDER BY count(id) desc;

/* X-ray <= 1.2 entries and disulfide bond count */
SELECT  pdb.id , count (cys_cys.pdb_id)
FROM    PDB pdb
        JOIN CYS_CYS cys_cys
            ON pdb.id = cys_cys.pdb_id
WHERE   pdb.exp_method = 'X-RAY DIFFRACTION'
  AND   pdb.resolution <= 1.2
  AND   pdb.status = 'CURRENT'
  /*AND   pdb.exp_method_identity_cutoff = '50'*/
  group by cys_cys.pdb_id 
  order by count(cys_cys.pdb_id) desc    

/* use left join to select all entries that have no viable disulfide bonds */
SELECT  DISTINCT pdb.id, cys_cys.pdb_id 
FROM    PDB pdb 
        LEFT JOIN CYS_CYS cys_cys 
            ON pdb.id = cys_cys.pdb_id
WHERE   cys_cys.pdb_id IS NULL 
  AND   pdb.status = 'CURRENT'
   
/* CYS_CYS entries with partial occupancy confi via sg_occ alt_id*/
SELECT distinct ss.id, ss.dse, conf.sg_occ
FROM   CYS_CONF conf
       JOIN CYS_CYS ss
        ON conf.id = ss.cys_conf_idi OR conf.id = ss.cys_conf_idj
WHERE  conf.sg_occ < 1 OR conf.alt_id IS NOT null    

/* 
  select pdb.id cys_cys.mol_code and cys_cys.dse for all 
  X-RAY Diffraction at or below 1.2 and sequence identity cutoff of 50
*/

SELECT  pdb.id, cys_cys.mol_code, cys_cys.dse 
FROM    PDB pdb 
        JOIN CYS_CYS cys_cys  
            ON pdb.id = cys_cys.pdb_id
WHERE   pdb.exp_method = 'X-RAY DIFFRACTION' 
  AND   pdb.resolution <= 1.2 
  AND   pdb.status = 'CURRENT' 
  AND   pdb.exp_method_identity_cutoff = '50' 
      
/* select all chains that have intrachain disulfide bonds */
SELECT  DISTINCT chain.pdb_id, chain.entity_id, chain.asym_id
FROM    Cys_Cys cys_cys
        JOIN PDB pdb
            ON pdb.id   = cys_cys.pdb_id
        JOIN Cys_Conf cysi
            ON cysi.id  = cys_cys.cys_conf_idi
        JOIN Cys cys
            ON cys.id   = cysi.cys_id
        JOIN Chain_Cys chain
            ON chain.id = cys.chain_id
WHERE   cys_cys.mol_code != 2
  AND   pdb.exp_method = 'X-RAY DIFFRACTION'
  AND   pdb.resolution <= 1.2
  AND   pdb.status = 'CURRENT'
  AND   pdb.exp_method_identity_cutoff = '50' 
  
/* count disulfides in specific chain */
SELECT  count(*)
FROM    Cys_Cys cys_cys
        JOIN Chain_Cys chain
            ON chain.id = cys_cys.chain_idi OR
                  chain.id = cys_cys.chain_idj
WHERE   cys_cys.pdb_id = '3S0A' 
    AND chain.asym_id = 'A'

/* average CA to CA distance for low-resolution entries matching IMMUNOGLOBULIN */
SELECT AVG(ss.CAi_CAj), AVG(ss.dse),COUNT(ss.id)
FROM CYS_CYS ss
		JOIN PDB pdb
			ON pdb.id = ss.pdb_id
WHERE exp_method = "X-RAY DIFFRACTION"
	AND keywords like "%IMMUNOGLOBULIN%"
	AND pdb.resolution > 1.5

/* display info for collection of pdb_ids discussed in publication*/
SELECT pdb.exp_method_identity_cutoff, pdb.id, chain.entity_id, chain.asym_id,  entity.sequence 
FROM   PDB pdb
       JOIN Chain_cys chain ON chain.pdb_id = pdb.id
       JOIN EntityCys entity ON entity.id = chain.entity_id
WHERE pdb.id in ('2KEI', '2KEJ', '2KEK', '1L1M', '1OSL')
