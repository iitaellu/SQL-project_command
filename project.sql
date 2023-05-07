--Views
CREATE VIEW employee_info AS 
SELECT employee.emp_name AS "name", employee.email AS "email", 
employee.contract_type AS "contract", employee.contract_start AS "contract started",
skills.skill AS "employee skills" 
FROM employee
INNER JOIN employee_skills ON employee.e_id = employee_skills.e_id
INNER JOIN skills ON employee_skills.s_id = skills.s_id;

CREATE VIEW customer_info AS 
SELECT customer.c_name AS "name", customer.email AS "email", 
customer.phone AS "phone", customer.c_type AS "type", 
geo_location.street AS "street", geo_location.city AS "city",
geo_location.country AS "country", project.project_name AS "project"
FROM customer
INNER JOIN geo_location ON customer.l_id = geo_location.l_id
INNER JOIN project ON customer.c_id = project.c_id
ORDER BY country, city, name;

CREATE VIEW employees_projects AS 
SELECT employee.emp_name AS "name", job_title.title AS "title", 
project.project_name AS "project"
FROM employee
INNER JOIN project_role ON employee.e_id = project_role.e_id
INNER JOIN job_title ON job_title.j_id = employee.j_id
INNER JOIN project ON project.p_id = project_role.p_id
INNER JOIN customer ON customer.c_id = project.c_id
ORDER BY project;

CREATE or replace VIEW projects AS 
SELECT project.project_name AS "project", project.budget AS "budget",
project.commission_percentage AS "commission%", project.p_start_date AS "start",
project.p_end_date AS "end", customer.c_name AS "customer",
employee.emp_name AS "has role", project_role.prole_start_date AS "started in role"
FROM project
INNER JOIN customer ON customer.c_id = project.c_id
INNER JOIN project_role ON project_role.p_id = project.p_id
INNER JOIN employee ON employee.e_id = project_role.e_id
ORDER BY project;

--Procedures

CREATE OR REPLACE PROCEDURE set_salary()
LANGUAGE plpgsql AS 
$$
BEGIN

	UPDATE employee SET salary = (SELECT base_salary FROM job_title
	WHERE employee.j_id = job_title.j_id);
	
END;
$$

CREATE OR REPLACE PROCEDURE add_three_month()
LANGUAGE 'plpgsql'
AS $$	
BEGIN

	UPDATE employee SET contract_end = contract_end + 3 * INTERVAL '1 MONTH'
	WHERE employee.contract_type = 'Temporary';
	
END;
$$

CREATE OR REPLACE PROCEDURE increase_salary(percentage INT, highest INT)
LANGUAGE 'plpgsql'
AS $$	
BEGIN
	
	if(highest <> 0 OR null) THEN
		UPDATE employee SET salary = salary+(salary*percentage/100) 
		WHERE salary <= highest;
	ELSE
		UPDATE employee SET salary = salary+(salary*percentage/100);
	END IF;
	
END;
$$

--Partitions
CREATE TABLE employee_partition (
	e_id integer NOT NULL,
    emp_name character varying,
    email character varying,
    contract_type character varying,
    contract_start date NOT NULL,
    contract_end date,
    salary integer DEFAULT 0,
    supervisor integer,
    d_id integer,
    j_id integer
) PARTITION BY LIST(contract_type);

CREATE TABLE employees_default PARTITION OF employee_partition DEFAULT;

CREATE TABLE employees_firsthalf PARTITION OF employee_partition
	FOR VALUES IN ('Temporary');

CREATE TABLE employees_secondhalf PARTITION OF employee_partition
	FOR VALUES IN ('Part-time');

CREATE TABLE employees_thirdhalf PARTITION OF employee_partition
	FOR VALUES IN ('Full-time');
	

INSERT INTO employee_partition SELECT * FROM employee;


CREATE TABLE project_partition (
	p_id integer NOT NULL,
    project_name character varying,
    budget numeric,
    commission_percentage numeric,
    p_start_date date,
    p_end_date date,
    c_id integer
) PARTITION BY Range(project_name);

CREATE TABLE project_default PARTITION OF project_partition DEFAULT;

CREATE TABLE project_firsthalf PARTITION OF project_partition
	FOR VALUES FROM ('A') TO ('I');

CREATE TABLE project_secondhalf PARTITION OF project_partition
	FOR VALUES FROM ('I') TO ('R');

CREATE TABLE project_thirdhalf PARTITION OF project_partition
	FOR VALUES FROM ('R') TO ('Z');
	

INSERT INTO project_partition SELECT * FROM project;

--Access rights

--Option 1
CREATE ROLE admin SUPERUSER;

--Option 2
CREATE ROLE admin;
GRANT ALL ON ALL TABLES IN SCHEMA public TO admin;

CREATE ROLE employee;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO employee;

CREATE ROLE trainee;
GRANT SELECT ON project, customer, geo_location, project_role TO trainee;
GRANT SELECT (e_id, emp_name, email) ON employee to trainee;

-- Changes to database

ALTER TABLE geo_location ADD zip_code varchar(5);

ALTER TABLE customer ALTER COLUMN email SET NOT NULL;
ALTER TABLE project ALTER COLUMN p_start_date SET NOT NULL;

ALTER TABLE employee ADD CONSTRAINT salary_check CHECK (salary > 1000);

-- Triggers

CREATE OR REPLACE FUNCTION checkIfSkillExists() 
RETURNS trigger AS 
$$	
	BEGIN
		
		IF EXISTS (select 1 FROM skills WHERE skill = NEW.skill) THEN
			RAISE EXCEPTION 'Skill already exists';
			RETURN NULL;
		ELSE
			RETURN NEW;
		END IF;
	
	END;

$$ LANGUAGE plpgsql;

CREATE TRIGGER checkSkill BEFORE INSERT OR UPDATE ON skills
FOR EACH ROW EXECUTE PROCEDURE checkIfSkillExists();

CREATE OR REPLACE FUNCTION updateEmployeeContract() 
RETURNS trigger AS 
$$	

	DECLARE
	type VARCHAR;
	start_d DATE;
	end_d DATE;
	
	BEGIN
	
		type = (SELECT contract_type FROM employee
			   WHERE NEW.e_id = employee.e_id);
		
		IF (type <> NEW.contract_type) THEN
			start_d = (SELECT CURRENT_DATE);
			NEW.contract_start=start_d;
			IF (NEW.contract_type = 'Temporary') THEN
				end_d = start_d +2*INTERVAL '1 YEAR';
				NEW.contract_end=end_d;
				RETURN NEW;			
			ELSE
				NEW..contract_end=NULL;
				RETURN NEW;			
			END IF;
		ELSE
			RETURN NEW;
		END IF;
	END;

$$ LANGUAGE plpgsql;

CREATE TRIGGER updateingEmployeeContract BEFORE INSERT OR UPDATE ON employee
FOR EACH ROW EXECUTE PROCEDURE updateEmployeeContract();

CREATE OR REPLACE FUNCTION insertNewProjectRoles()
RETURNS trigger AS
$$
DECLARE
	wanted_country VARCHAR;
	location_id INT;
	employee1 INT;
	employee2 INT;
	employee3 INT;
	BEGIN
		location_id = (SELECT l_id FROM customer WHERE customer.l_id = NEW.c_id);
		wanted_country = (SELECT country FROM geo_location 
						  Inner JOIN customer ON customer.l_id = geo_location.l_id 
						  WHERE customer.c_id = NEW.c_id);
		
		employee1 = (SELECT e_id FROM employee 
					 INNER JOIN department ON department.d_id = employee.d_id
					 INNER JOIN headquarters ON headquarters.h_id = department.hid
					 INNER JOIN geo_location ON geo_location.l_id = headquarters.l_id
					 WHERE geo_location.country = wanted_country
					 LIMIT 1);
					 
		employee2 = (SELECT e_id FROM employee 
					 INNER JOIN department ON department.d_id = employee.d_id
					 INNER JOIN headquarters ON headquarters.h_id = department.hid
					 INNER JOIN geo_location ON geo_location.l_id = headquarters.l_id
					 WHERE geo_location.country = wanted_country
					 AND e_id <> employee1
					 LIMIT 1);
		
		employee3 = (SELECT e_id FROM employee 
					 INNER JOIN department ON department.d_id = employee.d_id
					 INNER JOIN headquarters ON headquarters.h_id = department.hid
					 INNER JOIN geo_location ON geo_location.l_id = headquarters.l_id
					 WHERE geo_location.country = wanted_country
					 AND e_id <> employee1
					 AND e_id <> employee2
					 LIMIT 1);
		
		INSERT INTO project_role VALUES (employee1, NEW.p_id, NEW.p_start_date);
		INSERT INTO project_role VALUES (employee2, NEW.p_id, NEW.p_start_date);
		INSERT INTO project_role VALUES (employee3, NEW.p_id, NEW.p_start_date);
		
		RETURN NEW;
	END;
	
$$

CREATE TRIGGER insertNewProjectRoles AFTER INSERT project
FOR EACH ROW PROCEDURE insertNewProjectRoles;

