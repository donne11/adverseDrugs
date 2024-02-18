-- HW5: Identifying Adverse Drug Events (ADEs) with Stored Programs
-- Prof. Rachlin
-- CS 3200 / CS5200: Databases

-- We've already setup the ade database by running ade_setup.sql
-- First, make ade the active database.  Note, this database is actually based on
-- the emr_sp schema used in the lab, but it included some extra tables.

use ade;



-- A stored procedure to process and validate prescriptions
-- Four things we need to check
-- a) Is patient a child and is medication suitable for children?
-- b) Is patient pregnant and is medication suitable for pregnant women?
-- c) Are there any adverse drug reactions


drop procedure if exists prescribe;

delimiter //

create procedure prescribe
(
    in patient_name_param varchar(255),
    in doctor_name_param varchar(255),
    in medication_name_param varchar(255),
    in ppd_param int -- pills per day prescribed
)
begin
	-- variable declarations
    declare patient_id_var int;
    declare age_var float;
    declare is_pregnant_var boolean;
    declare weight_var int;
    declare doctor_id_var int;
    declare medication_id_var int;
    declare take_under_12_var boolean;
    declare take_if_pregnant_var boolean;
    declare mg_per_pill_var double;
    declare max_mg_per_10kg_var double;

    declare message varchar(255); -- The error message
    declare ddi_medication varchar(255); -- The name of a medication involved in a drug-drug interaction

    -- select relevant values into variables
    
    SELECT patient_id, dob, is_pregnant, weight, pcp_id
    INTO patient_id_var, age_var, is_pregnant_var, weight_var, doctor_id_var
    FROM patient
    WHERE patient_name = patient_name_param;


    -- check age of patient
   
  SELECT take_under_12, medication_id
    INTO take_under_12_var, medication_id_var
    FROM medication
    WHERE medication_name = medication_name_param;

    -- reject prescription for patient under 12
    IF age_var <= 11 AND NOT take_under_12_var THEN
        SET message = CONCAT("Children cannot have  ", medication_name_param);
        SIGNAL SQLSTATE "45000" SET MESSAGE_TEXT = message;
    END IF;



    -- check if medication ok for pregnant women
    
	SELECT take_if_pregnant, medication_id
	INTO take_if_pregnant_var, medication_id_var
	FROM medication
	WHERE medication_name = medication_name_param;

	-- Check if the medication was found
	IF take_if_pregnant_var IS NULL THEN
		-- Medication not found, handle this case (perhaps throw an error)
		SET message = CONCAT("Medication ", medication_name_param, " not found.");
		SIGNAL SQLSTATE "45000" SET MESSAGE_TEXT = message;
	END IF;

	-- Check if the medication is not suitable for pregnant women
	IF is_pregnant_var = 1 AND take_if_pregnant_var = FALSE THEN
		SET message = CONCAT(medication_name_param, " cannot be prescribed to pregnant women.");
		SIGNAL SQLSTATE "45000" SET MESSAGE_TEXT = message;
	END IF;



    -- Check for reactions involving medications already prescribed to patient
	SELECT COALESCE(interaction.medication_2, interaction.medication_1) INTO ddi_medication
	FROM interaction
	JOIN prescription ON (interaction.medication_1 = prescription.medication_id OR interaction.medication_2 = prescription.medication_id)
	WHERE prescription.patient_id = patient_id_var AND (interaction.medication_1 = medication_id_var OR interaction.medication_2 = medication_id_var)
    LIMIT 1;
    
	-- Check if theres drug interaction
	IF ddi_medication IS NOT NULL THEN
		BEGIN
			SET message = CONCAT("Adeverse Affect ", ddi_medication);
			SIGNAL SQLSTATE "45000" SET MESSAGE_TEXT = message;
		END;
	ELSE
		-- No exceptions thrown, so insert the prescription record
		INSERT INTO prescription (medication_id, patient_id, doctor_id, ppd)
		VALUES (medication_id_var, patient_id_var, (SELECT doctor_id FROM doctor WHERE doctor_name = doctor_name_param), ppd_param);
	END IF;
end //
delimiter ;





-- Trigger

DROP TRIGGER IF EXISTS patient_after_update_pregnant;

DELIMITER //

CREATE TRIGGER patient_after_update_pregnant
	AFTER UPDATE ON patient
	FOR EACH ROW
BEGIN

-- Patient became pregnant
IF NEW.is_pregnant = 1 AND OLD.is_pregnant = 0 THEN
    -- Add pre-natal recommendation
    INSERT INTO recommendation (patient_id, message)
    VALUES (NEW.patient_id, "Pre-natal recommendation");
    
    -- Delete any prescriptions that shouldn't be taken if pregnant
    DELETE FROM prescription
    WHERE patient_id = NEW.patient_id AND medication_id IN (
        SELECT medication_id
        FROM medication
        WHERE take_if_pregnant = 0
    );

-- Patient is no longer pregnant
ELSEIF NEW.is_pregnant = 0 AND OLD.is_pregnant = 1 THEN
    -- Remove pre-natal recommendation
    DELETE FROM recommendation
    WHERE patient_id = NEW.patient_id AND message = "Pre-natal recommendation";
END IF;

END //

DELIMITER ;




-- --------------------------                  TEST CASES                     -----------------------
-- -------------------------- DONT CHANGE BELOW THIS LINE! -----------------------
-- Test cases
truncate prescription;

-- These prescriptions should succeed
call prescribe('Jones', 'Dr.Marcus', 'Happyza', 2);
call prescribe('Johnson', 'Dr.Marcus', 'Forgeta', 1);
call prescribe('Williams', 'Dr.Marcus', 'Happyza', 1);
call prescribe('Phillips', 'Dr.McCoy', 'Forgeta', 1);

-- These prescriptions should fail
-- Pregnancy violation
call prescribe('Jones', 'Dr.Marcus', 'Forgeta', 2);

-- Age restriction
call prescribe('BillyTheKid', 'Dr.Marcus', 'Muscula', 1);


-- Drug interaction
call prescribe('Williams', 'Dr.Marcus', 'Sadza', 1);



-- Testing trigger
-- Phillips (patient_id=4) becomes pregnant
-- Verify that a recommendation for pre-natal vitamins is added
-- and that her prescription for
update patient
set is_pregnant = True
where patient_id = 4;

select * from recommendation;
select * from prescription;


-- Phillips (patient_id=4) is no longer pregnant
-- Verify that the prenatal vitamin recommendation is gone
-- Her old prescription does not need to be added back

update patient
set is_pregnant = False
where patient_id = 4;

select * from recommendation;
