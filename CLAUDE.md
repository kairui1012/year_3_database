# GLCL SQL Project Instructions

IMPORTANT:
Before making any changes, ALWAYS read and understand `glcl.md`.

`glcl.md` contains:
- business rules
- assignment requirements
- entity relationships
- constraints
- grading expectations
- domain terminology

Never ignore or overwrite the business rules defined in `glcl.md`.

---

# Project Context

This project is a database system for:

GLOBAL LUXURY CRUISE LINES (GLCL)

The system manages:
- cruise operators
- ships
- cabins
- passengers
- bookings
- payments
- special services
- baggage
- cruise schedules

The project is an academic SQL/database assignment.

---

# Database Standards

Use:
- MySQL 8+
- Standard SQL formatting
- Uppercase SQL keywords
- Singular table names
- Meaningful constraint names

Example:

CREATE TABLE Passenger (
    PassengerID INT AUTO_INCREMENT PRIMARY KEY,
    FullName VARCHAR(100) NOT NULL
);

---

# Naming Conventions

## Tables
- Use PascalCase
- Singular nouns

Examples:
- Passenger
- Booking
- Cabin
- CruiseSchedule

## Columns
- Use PascalCase
- Primary keys should end with ID

Examples:
- PassengerID
- BookingDate
- CabinType

## Constraints

Primary Key:
PK_TableName

Foreign Key:
FK_Child_Parent

Check Constraint:
CK_Table_Column

Unique Constraint:
UQ_Table_Column

Examples:
- FK_Booking_Passenger
- CK_Cabin_MaxCapacity

---

# Business Rules

Follow all business rules from `glcl.md`.

Important examples include:
- cabin passenger limits
- age restrictions
- infant and child pricing rules
- booking restrictions
- cancellation policies
- adjacent cabin requirements for minors

Never invent business logic that conflicts with `glcl.md`.

---

# Query Standards

When writing SQL queries:
- format queries clearly
- use aliases consistently
- avoid SELECT *
- explain complex joins
- optimize unnecessary nested queries

Preferred style:

SELECT p.FullName,
       b.BookingDate
FROM Passenger p
JOIN Booking b
    ON p.PassengerID = b.PassengerID;

---

# Stored Procedures / Triggers

When creating:
- procedures
- triggers
- functions
- views

Always:
- explain purpose first
- keep logic modular
- avoid duplicated logic
- validate important constraints

---

# Assignment Goals

Prioritize:
1. correctness
2. normalization
3. maintainability
4. readability
5. business rule accuracy

Do not overengineer.

This is an academic database project, not a production microservice architecture.

---

# Response Behavior

Before generating SQL:
1. Read `glcl.md`
2. Understand related entities
3. Check business rules
4. Preserve schema consistency

If requirements are unclear:
- infer conservatively
- avoid breaking existing relationships

Never randomly rename tables or columns.
Never delete constraints unless explicitly requested.