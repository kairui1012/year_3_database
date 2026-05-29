/*
 * ============================================================
 *  GLOBAL LUXURY CRUISE LINES (GLCL)
 *  MySQL 8+ Database Script
 *
 *  Scope:
 *    - Cruise reservations
 *    - Cabin and passenger management
 *    - Dining, special services, and baggage
 *    - Onshore excursions
 *    - Cancellations and rescheduling
 *    - Payments
 *
 *  Standards:
 *    - MySQL 8.0 or above
 *    - 3NF normalisation unless noted otherwise
 *    - PascalCase table and column names
 *    - Constraint naming: PK_, FK_, CK_, UQ_
 * ============================================================
 */

DROP DATABASE IF EXISTS GLCL_DB;
CREATE DATABASE GLCL_DB;
USE GLCL_DB;

/* ============================================================
   SECTION 1: OPERATOR, SHIP, AND CABIN
   ============================================================ */

/*
 * CruiseOperator
 * Stores each cruise operator managed by GLCL.
 * AllowsChaperonedYouth controls whether the operator offers
 * the supervised teen travel programme for ages 15–17.
 */
CREATE TABLE CruiseOperator (
    OperatorID             INT           AUTO_INCREMENT PRIMARY KEY,
    OperatorName           VARCHAR(150)  NOT NULL UNIQUE,
    HeadquartersCountry    VARCHAR(100)  NOT NULL,
    ContactEmail           VARCHAR(150),
    AllowsChaperonedYouth  BOOLEAN       NOT NULL DEFAULT FALSE
);

/*
 * CruiseShip
 * A ship belongs to exactly one operator.
 * ShipName must be unique within the same operator.
 */
CREATE TABLE CruiseShip (
    ShipID             INT           AUTO_INCREMENT PRIMARY KEY,
    OperatorID         INT           NOT NULL,
    ShipName           VARCHAR(150)  NOT NULL,
    TotalDecks         INT           NOT NULL,
    PassengerCapacity  INT           NOT NULL,
    CONSTRAINT FK_CruiseShip_CruiseOperator
        FOREIGN KEY (OperatorID) REFERENCES CruiseOperator(OperatorID),
    CONSTRAINT UQ_CruiseShip_Operator_ShipName
        UNIQUE (OperatorID, ShipName)
);

/*
 * CabinCategory
 * Lookup table for the four permitted cabin types:
 *   Interior | Ocean View | Balcony | Suite
 */
CREATE TABLE CabinCategory (
    CabinCategoryID      INT           AUTO_INCREMENT PRIMARY KEY,
    CategoryName         VARCHAR(50)   NOT NULL UNIQUE,
    CategoryDescription  VARCHAR(255)
);

/*
 * Cabin
 * Physical cabin on a specific ship.
 * Business rule: maximum occupancy is 5 passengers per cabin.
 * IsWheelchairAccessible supports the accessibility service requirement.
 */
CREATE TABLE Cabin (
    CabinID                INT           AUTO_INCREMENT PRIMARY KEY,
    ShipID                 INT           NOT NULL,
    CabinCategoryID        INT           NOT NULL,
    CabinNumber            VARCHAR(20)   NOT NULL,
    DeckNumber             INT           NOT NULL,
    MaxOccupancy           INT           NOT NULL,
    IsWheelchairAccessible BOOLEAN       NOT NULL DEFAULT FALSE,
    CONSTRAINT FK_Cabin_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_Cabin_CabinCategory
        FOREIGN KEY (CabinCategoryID) REFERENCES CabinCategory(CabinCategoryID),
    -- Business rule: strict maximum of 5 passengers per cabin
    CONSTRAINT CK_Cabin_MaxOccupancy
        CHECK (MaxOccupancy BETWEEN 1 AND 5),
    CONSTRAINT UQ_Cabin_Ship_CabinNumber
        UNIQUE (ShipID, CabinNumber)
);

/*
 * CabinAdjacency
 * Records which cabins are physically adjacent or connecting.
 * Business rule: a minor (age ≤ 17) may occupy a cabin without
 * an adult in the same cabin ONLY if an adult guardian is booked
 * in an adjacent or connecting cabin on the same voyage.
 * Rows must be inserted bidirectionally (A→B and B→A).
 */
CREATE TABLE CabinAdjacency (
    CabinAdjacencyID  INT          AUTO_INCREMENT PRIMARY KEY,
    CabinID           INT          NOT NULL,
    AdjacentCabinID   INT          NOT NULL,
    AdjacencyType     VARCHAR(20)  NOT NULL DEFAULT 'Adjacent',
    CONSTRAINT FK_CabinAdjacency_Cabin
        FOREIGN KEY (CabinID) REFERENCES Cabin(CabinID),
    CONSTRAINT FK_CabinAdjacency_AdjacentCabin
        FOREIGN KEY (AdjacentCabinID) REFERENCES Cabin(CabinID),
    CONSTRAINT CK_CabinAdjacency_NotSelf
        CHECK (CabinID <> AdjacentCabinID),
    CONSTRAINT UQ_CabinAdjacency
        UNIQUE (CabinID, AdjacentCabinID)
);

/* ============================================================
   SECTION 2: ROUTE AND VOYAGE
   ============================================================ */

/*
 * CruiseRoute
 * Defines the sailing itinerary type:
 *   One-way | Round-trip | Multi-destination
 */
CREATE TABLE CruiseRoute (
    RouteID    INT           AUTO_INCREMENT PRIMARY KEY,
    RouteName  VARCHAR(150)  NOT NULL,
    RouteType  VARCHAR(30)   NOT NULL
);

/*
 * Port
 * A port of call or home port used in cruise routes.
 * Unique on (PortName, Country) to avoid duplicate entries.
 */
CREATE TABLE Port (
    PortID    INT           AUTO_INCREMENT PRIMARY KEY,
    PortName  VARCHAR(150)  NOT NULL,
    Country   VARCHAR(100)  NOT NULL,
    CONSTRAINT UQ_Port_Name_Country
        UNIQUE (PortName, Country)
);

/*
 * RoutePort
 * Junction between a route and its ports, ordered by StopSequence.
 * IsHomePort marks the departure/home port of the itinerary.
 */
CREATE TABLE RoutePort (
    RoutePortID    INT      AUTO_INCREMENT PRIMARY KEY,
    RouteID        INT      NOT NULL,
    PortID         INT      NOT NULL,
    StopSequence   INT      NOT NULL,
    IsHomePort     BOOLEAN  NOT NULL DEFAULT FALSE,
    CONSTRAINT FK_RoutePort_CruiseRoute
        FOREIGN KEY (RouteID) REFERENCES CruiseRoute(RouteID),
    CONSTRAINT FK_RoutePort_Port
        FOREIGN KEY (PortID) REFERENCES Port(PortID),
    CONSTRAINT UQ_RoutePort_Route_StopSequence
        UNIQUE (RouteID, StopSequence)
);

/*
 * CruiseVoyage
 * A specific scheduled sailing of a ship along a route.
 * VoyageLengthDays is a computed column (ArrivalDateTime - DepartureDateTime).
 * BaggageWeightLimitKG enforces the per-passenger baggage limit for this voyage.
 */
CREATE TABLE CruiseVoyage (
    VoyageID              INT             AUTO_INCREMENT PRIMARY KEY,
    ShipID                INT             NOT NULL,
    RouteID               INT             NOT NULL,
    DepartureDateTime     DATETIME        NOT NULL,
    ArrivalDateTime       DATETIME        NOT NULL,
    -- Computed: number of days between departure and arrival
    VoyageLengthDays      INT             GENERATED ALWAYS AS (DATEDIFF(ArrivalDateTime, DepartureDateTime)) STORED,
    BaggageWeightLimitKG  DECIMAL(6,2)    NOT NULL,
    VoyageStatus          VARCHAR(30)     NOT NULL DEFAULT 'Scheduled',
    CONSTRAINT FK_CruiseVoyage_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_CruiseVoyage_CruiseRoute
        FOREIGN KEY (RouteID) REFERENCES CruiseRoute(RouteID),
    CONSTRAINT CK_CruiseVoyage_ArrivalAfterDeparture
        CHECK (ArrivalDateTime > DepartureDateTime)
);

/* ============================================================
   SECTION 3: PASSENGER, AGE CATEGORY, BOOKING
   ============================================================ */

/*
 * Passenger
 * A person who can be booked on a voyage.
 * PassportNo is globally unique (used as identity in bookings).
 */
CREATE TABLE Passenger (
    PassengerID  INT           AUTO_INCREMENT PRIMARY KEY,
    FullName     VARCHAR(150)  NOT NULL,
    DateOfBirth  DATE          NOT NULL,
    PassportNo   VARCHAR(50)   NOT NULL UNIQUE,
    Nationality  VARCHAR(100)  NOT NULL,
    Gender       VARCHAR(20),
    ContactNo    VARCHAR(30),
    Email        VARCHAR(150)
);

/*
 * AgeCategory
 * Lookup table for GLCL fare age bands:
 *   Infant (0–1) | Child (2–12) | Teen (13–17) | Adult (18–59) | Senior (60+)
 * MaxAge is NULL for the Senior category (no upper bound).
 */
CREATE TABLE AgeCategory (
    AgeCategoryID  INT          AUTO_INCREMENT PRIMARY KEY,
    CategoryName   VARCHAR(30)  NOT NULL UNIQUE,
    MinAge         INT          NOT NULL,
    MaxAge         INT          NULL,
    CONSTRAINT CK_AgeCategory_AgeRange
        CHECK (MinAge >= 0 AND (MaxAge IS NULL OR MaxAge >= MinAge))
);

/*
 * Booking
 * A reservation made by a customer (CustomerPassengerID) for a voyage.
 * TotalAmount is the sum of all passenger fares within this booking.
 * OriginalBookingID self-references the booking replaced by a reschedule.
 */
CREATE TABLE Booking (
    BookingID            INT             AUTO_INCREMENT PRIMARY KEY,
    BookingDate          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CustomerPassengerID  INT             NOT NULL,
    VoyageID             INT             NOT NULL,
    BookingStatus        VARCHAR(30)     NOT NULL DEFAULT 'Confirmed',
    TotalAmount          DECIMAL(12,2)   NOT NULL DEFAULT 0,
    -- NULL unless this booking replaced an earlier one via reschedule
    OriginalBookingID    INT             NULL,
    CONSTRAINT FK_Booking_CustomerPassenger
        FOREIGN KEY (CustomerPassengerID) REFERENCES Passenger(PassengerID),
    CONSTRAINT FK_Booking_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_Booking_OriginalBooking
        FOREIGN KEY (OriginalBookingID) REFERENCES Booking(BookingID),
    CONSTRAINT CK_Booking_Status
        CHECK (BookingStatus IN ('Pending', 'Confirmed', 'Waitlisted', 'Cancelled', 'Rescheduled', 'Completed'))
);

/*
 * BookingCabin
 * Links a booking to a specific cabin.
 * A cabin may only appear once per booking (UQ constraint).
 * Double-booking prevention for the same voyage is handled by trigger.
 */
CREATE TABLE BookingCabin (
    BookingCabinID  INT            AUTO_INCREMENT PRIMARY KEY,
    BookingID       INT            NOT NULL,
    CabinID         INT            NOT NULL,
    CabinPrice      DECIMAL(12,2)  NOT NULL DEFAULT 0,
    CONSTRAINT FK_BookingCabin_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_BookingCabin_Cabin
        FOREIGN KEY (CabinID) REFERENCES Cabin(CabinID),
    CONSTRAINT UQ_BookingCabin_Booking_Cabin
        UNIQUE (BookingID, CabinID)
);

/*
 * FareRule
 * Defines the base fare for a (Voyage, CabinCategory, AgeCategory) combination.
 * EffectiveFrom/EffectiveTo allow time-limited fare changes.
 * Infant fares are NOT stored here — they are computed dynamically from
 * Adult and Child fares in the BookingPassenger insert trigger.
 */
CREATE TABLE FareRule (
    FareRuleID       INT            AUTO_INCREMENT PRIMARY KEY,
    VoyageID         INT            NOT NULL,
    CabinCategoryID  INT            NOT NULL,
    AgeCategoryID    INT            NOT NULL,
    BaseFare         DECIMAL(12,2)  NOT NULL,
    EffectiveFrom    DATE           NOT NULL,
    EffectiveTo      DATE           NULL,
    CONSTRAINT FK_FareRule_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_FareRule_CabinCategory
        FOREIGN KEY (CabinCategoryID) REFERENCES CabinCategory(CabinCategoryID),
    CONSTRAINT FK_FareRule_AgeCategory
        FOREIGN KEY (AgeCategoryID) REFERENCES AgeCategory(AgeCategoryID),
    CONSTRAINT UQ_FareRule_Voyage_Category_Age_Date
        UNIQUE (VoyageID, CabinCategoryID, AgeCategoryID, EffectiveFrom)
);

/*
 * BookingPassenger
 * Links a specific passenger to a cabin within a booking.
 * FinalFare is automatically computed by the insert/update trigger:
 *   - Infant (SharedBed): 15% of adult base fare
 *   - Infant (Cot):       50% of child base fare
 *   - All others:         base fare from FareRule
 * DailySupervisionFee is set by the trigger when IsChaperonedYouth = TRUE.
 */
CREATE TABLE BookingPassenger (
    BookingPassengerID    INT            AUTO_INCREMENT PRIMARY KEY,
    BookingID             INT            NOT NULL,
    BookingCabinID        INT            NOT NULL,
    PassengerID           INT            NOT NULL,
    AgeCategoryID         INT            NOT NULL,
    -- NULL for infants (fare is derived, not from a FareRule row)
    FareRuleID            INT            NULL,
    -- 'SharedBed' or 'Cot' for infants; 'NotApplicable' for all others
    InfantBedOption       VARCHAR(20)    NOT NULL DEFAULT 'NotApplicable',
    IsChaperonedYouth     BOOLEAN        NOT NULL DEFAULT FALSE,
    -- Set by trigger from SpecialService.Fee where ServiceType = 'Chaperoned Youth'
    DailySupervisionFee   DECIMAL(10,2)  NOT NULL DEFAULT 0,
    -- Computed and set by trigger on insert/update
    FinalFare             DECIMAL(12,2)  NOT NULL DEFAULT 0,
    CONSTRAINT FK_BookingPassenger_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_BookingPassenger_BookingCabin
        FOREIGN KEY (BookingCabinID) REFERENCES BookingCabin(BookingCabinID),
    CONSTRAINT FK_BookingPassenger_Passenger
        FOREIGN KEY (PassengerID) REFERENCES Passenger(PassengerID),
    CONSTRAINT FK_BookingPassenger_AgeCategory
        FOREIGN KEY (AgeCategoryID) REFERENCES AgeCategory(AgeCategoryID),
    CONSTRAINT FK_BookingPassenger_FareRule
        FOREIGN KEY (FareRuleID) REFERENCES FareRule(FareRuleID),
    CONSTRAINT CK_BookingPassenger_InfantBedOption
        CHECK (InfantBedOption IN ('SharedBed', 'Cot', 'NotApplicable')),
    -- A passenger can only appear once per booking
    CONSTRAINT UQ_BookingPassenger_Booking_Passenger
        UNIQUE (BookingID, PassengerID)
);

/* ============================================================
   SECTION 4: DINING
   ============================================================ */

/*
 * DiningOption
 * The three dining styles available on GLCL ships.
 */
CREATE TABLE DiningOption (
    DiningOptionID  INT           AUTO_INCREMENT PRIMARY KEY,
    DiningName      VARCHAR(100)  NOT NULL UNIQUE
);

/*
 * ShipDiningOption
 * Many-to-many: which dining options a specific ship offers.
 */
CREATE TABLE ShipDiningOption (
    ShipDiningOptionID  INT  AUTO_INCREMENT PRIMARY KEY,
    ShipID              INT  NOT NULL,
    DiningOptionID      INT  NOT NULL,
    CONSTRAINT FK_ShipDiningOption_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_ShipDiningOption_DiningOption
        FOREIGN KEY (DiningOptionID) REFERENCES DiningOption(DiningOptionID),
    CONSTRAINT UQ_ShipDiningOption_Ship_DiningOption
        UNIQUE (ShipID, DiningOptionID)
);

/*
 * SpecialtyDiningType
 * Cuisine or dietary categories offered at specialty restaurants
 * (e.g., Vegan, Gluten-Free, Halal, Kosher).
 */
CREATE TABLE SpecialtyDiningType (
    SpecialtyDiningTypeID  INT           AUTO_INCREMENT PRIMARY KEY,
    TypeName               VARCHAR(100)  NOT NULL UNIQUE,
    Description            VARCHAR(255)
);

/*
 * ShipSpecialtyDining
 * Many-to-many: which specialty dining types a specific ship provides.
 */
CREATE TABLE ShipSpecialtyDining (
    ShipSpecialtyDiningID  INT  AUTO_INCREMENT PRIMARY KEY,
    ShipID                 INT  NOT NULL,
    SpecialtyDiningTypeID  INT  NOT NULL,
    CONSTRAINT FK_ShipSpecialtyDining_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_ShipSpecialtyDining_SpecialtyDiningType
        FOREIGN KEY (SpecialtyDiningTypeID) REFERENCES SpecialtyDiningType(SpecialtyDiningTypeID),
    CONSTRAINT UQ_ShipSpecialtyDining_Ship_Type
        UNIQUE (ShipID, SpecialtyDiningTypeID)
);

/*
 * VoyageMealPackageType
 * Two possible meal package types based on voyage length:
 *   - Standard boarding meal   (1-day voyages)
 *   - Multi-day all-inclusive  (2+ day voyages)
 */
CREATE TABLE VoyageMealPackageType (
    MealPackageTypeID  INT           AUTO_INCREMENT PRIMARY KEY,
    PackageName        VARCHAR(100)  NOT NULL UNIQUE
);

/*
 * VoyageMealPackageRule
 * Maps a voyage length band to a meal package type.
 * MaxVoyageLengthDays is NULL for open-ended upper bounds.
 */
CREATE TABLE VoyageMealPackageRule (
    MealPackageRuleID    INT  AUTO_INCREMENT PRIMARY KEY,
    MealPackageTypeID    INT  NOT NULL,
    MinVoyageLengthDays  INT  NOT NULL,
    MaxVoyageLengthDays  INT  NULL,
    CONSTRAINT FK_VoyageMealPackageRule_VoyageMealPackageType
        FOREIGN KEY (MealPackageTypeID) REFERENCES VoyageMealPackageType(MealPackageTypeID),
    CONSTRAINT UQ_VoyageMealPackageRule_LengthBand
        UNIQUE (MinVoyageLengthDays, MaxVoyageLengthDays)
);

/*
 * VoyageMealPackage
 * Assigns the applicable meal package rule to a specific voyage.
 * Each voyage has exactly one meal package (unique on VoyageID).
 */
CREATE TABLE VoyageMealPackage (
    VoyageMealPackageID  INT  AUTO_INCREMENT PRIMARY KEY,
    VoyageID             INT  NOT NULL,
    MealPackageRuleID    INT  NOT NULL,
    CONSTRAINT FK_VoyageMealPackage_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_VoyageMealPackage_VoyageMealPackageRule
        FOREIGN KEY (MealPackageRuleID) REFERENCES VoyageMealPackageRule(MealPackageRuleID),
    CONSTRAINT UQ_VoyageMealPackage_Voyage
        UNIQUE (VoyageID)
);

/* ============================================================
   SECTION 5: SPECIAL SERVICES AND BAGGAGE
   ============================================================ */

/*
 * SpecialService
 * Defines available special services and their age restrictions.
 * Types: Childcare | Teen Club | Accessibility | Mobility | Chaperoned Youth
 * Fee for 'Chaperoned Youth' is used by the trigger as DailySupervisionFee.
 */
CREATE TABLE SpecialService (
    ServiceID          INT            AUTO_INCREMENT PRIMARY KEY,
    ServiceName        VARCHAR(100)   NOT NULL UNIQUE,
    ServiceType        VARCHAR(50)    NOT NULL,
    AgeRestrictionMin  INT            NULL,
    AgeRestrictionMax  INT            NULL,
    Fee                DECIMAL(10,2)  NOT NULL DEFAULT 0
);

/*
 * PassengerSpecialService
 * Records a special service request for a specific booked passenger.
 * One passenger cannot request the same service twice (UQ constraint).
 */
CREATE TABLE PassengerSpecialService (
    PassengerServiceID  INT            AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID  INT            NOT NULL,
    ServiceID           INT            NOT NULL,
    RequestStatus       VARCHAR(30)    NOT NULL DEFAULT 'Requested',
    Fee                 DECIMAL(10,2)  NOT NULL DEFAULT 0,
    CONSTRAINT FK_PassengerSpecialService_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT FK_PassengerSpecialService_SpecialService
        FOREIGN KEY (ServiceID) REFERENCES SpecialService(ServiceID),
    CONSTRAINT UQ_PassengerSpecialService_Passenger_Service
        UNIQUE (BookingPassengerID, ServiceID)
);

/*
 * BaggageRule
 * Per-operator baggage weight rules with effective date ranges.
 * EffectiveTo NULL means the rule is currently in force.
 */
CREATE TABLE BaggageRule (
    BaggageRuleID  INT            AUTO_INCREMENT PRIMARY KEY,
    OperatorID     INT            NOT NULL,
    MaxWeightKG    DECIMAL(6,2)   NOT NULL,
    EffectiveFrom  DATE           NOT NULL,
    EffectiveTo    DATE           NULL,
    CONSTRAINT FK_BaggageRule_CruiseOperator
        FOREIGN KEY (OperatorID) REFERENCES CruiseOperator(OperatorID)
);

/*
 * BookingBaggage
 * Records the actual baggage weight declared for a booked passenger.
 * IsOverLimit and ExcessFee are set automatically by the insert/update trigger,
 * comparing WeightKG against the voyage's BaggageWeightLimitKG.
 */
CREATE TABLE BookingBaggage (
    BaggageID           INT            AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID  INT            NOT NULL,
    WeightKG            DECIMAL(6,2)   NOT NULL,
    -- Computed by trigger: TRUE if WeightKG exceeds voyage limit
    IsOverLimit         BOOLEAN        NOT NULL DEFAULT FALSE,
    ExcessFee           DECIMAL(10,2)  NOT NULL DEFAULT 0,
    CONSTRAINT FK_BookingBaggage_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID)
);

/* ============================================================
   SECTION 6: ONSHORE EXCURSIONS
   ============================================================ */

/*
 * Excursion
 * An activity available at a specific port of call.
 * Unique on (PortID, ExcursionName) to avoid duplicate entries per port.
 */
CREATE TABLE Excursion (
    ExcursionID    INT            AUTO_INCREMENT PRIMARY KEY,
    PortID         INT            NOT NULL,
    ExcursionName  VARCHAR(150)   NOT NULL,
    Description    VARCHAR(500),
    DurationHours  DECIMAL(5,2)   NOT NULL,
    Price          DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    CONSTRAINT FK_Excursion_Port
        FOREIGN KEY (PortID) REFERENCES Port(PortID),
    CONSTRAINT UQ_Excursion_Port_Name
        UNIQUE (PortID, ExcursionName)
);

/*
 * VoyageExcursion
 * Links an excursion to a specific route stop (RoutePort) on a voyage,
 * and tracks available slot capacity.
 */
CREATE TABLE VoyageExcursion (
    VoyageExcursionID  INT  AUTO_INCREMENT PRIMARY KEY,
    VoyageID           INT  NOT NULL,
    RoutePortID        INT  NOT NULL,
    ExcursionID        INT  NOT NULL,
    AvailableSlots     INT  NOT NULL DEFAULT 0,
    CONSTRAINT FK_VoyageExcursion_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_VoyageExcursion_RoutePort
        FOREIGN KEY (RoutePortID) REFERENCES RoutePort(RoutePortID),
    CONSTRAINT FK_VoyageExcursion_Excursion
        FOREIGN KEY (ExcursionID) REFERENCES Excursion(ExcursionID),
    CONSTRAINT UQ_VoyageExcursion_Voyage_Port_Excursion
        UNIQUE (VoyageID, RoutePortID, ExcursionID)
);

/*
 * BookingExcursion
 * Records a passenger's purchase of a voyage excursion.
 * Used to identify sold and unsold excursions via LEFT JOIN queries.
 */
CREATE TABLE BookingExcursion (
    BookingExcursionID  INT            AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID  INT            NOT NULL,
    VoyageExcursionID   INT            NOT NULL,
    BookingDateTime     DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ExcursionStatus     VARCHAR(30)    NOT NULL DEFAULT 'Booked',
    AmountPaid          DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    CONSTRAINT FK_BookingExcursion_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT FK_BookingExcursion_VoyageExcursion
        FOREIGN KEY (VoyageExcursionID) REFERENCES VoyageExcursion(VoyageExcursionID),
    -- A passenger can book the same excursion only once
    CONSTRAINT UQ_BookingExcursion_Passenger_Excursion
        UNIQUE (BookingPassengerID, VoyageExcursionID)
);

/* ============================================================
   SECTION 7: CANCELLATION, RESCHEDULING, AND PAYMENT
   ============================================================ */

/*
 * CancellationPolicy
 * Per-operator rules that define how penalties are applied based on
 * how far in advance of departure the cancellation is made.
 * PenaltyType: Percentage | FixedAmount | FullForfeit
 */
CREATE TABLE CancellationPolicy (
    PolicyID               INT            AUTO_INCREMENT PRIMARY KEY,
    OperatorID             INT            NOT NULL,
    HoursBeforeDeparture   INT            NOT NULL,
    PenaltyType            VARCHAR(30)    NOT NULL,
    PenaltyValue           DECIMAL(10,2)  NOT NULL,
    CONSTRAINT FK_CancellationPolicy_CruiseOperator
        FOREIGN KEY (OperatorID) REFERENCES CruiseOperator(OperatorID),
    CONSTRAINT CK_CancellationPolicy_PenaltyType
        CHECK (PenaltyType IN ('Percentage', 'FixedAmount', 'FullForfeit'))
);

/*
 * BookingCancellation
 * Records a cancellation event for a booking.
 * PenaltyAmount and RefundAmount are computed automatically by the
 * BEFORE INSERT trigger using the operator's CancellationPolicy.
 * The AFTER INSERT trigger then marks the Booking status as 'Cancelled'.
 * Business rule: cancellation < 48 hours before departure forfeits full fare.
 */
CREATE TABLE BookingCancellation (
    CancellationID        INT            AUTO_INCREMENT PRIMARY KEY,
    BookingID             INT            NOT NULL UNIQUE,
    CancellationDateTime  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Reason                VARCHAR(255),
    -- Computed by trigger
    PenaltyAmount         DECIMAL(12,2)  NOT NULL DEFAULT 0,
    RefundAmount          DECIMAL(12,2)  NOT NULL DEFAULT 0,
    ProcessedBy           VARCHAR(100),
    CONSTRAINT FK_BookingCancellation_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID)
);

/*
 * RescheduleRequest
 * Tracks a request to move a booking to a different voyage.
 * Business rules (enforced by trigger):
 *   1. Cannot reschedule after the original voyage has departed.
 *   2. New voyage must start within one year of the original booking date.
 *   3. Rescheduling < 48 hours before departure charges the full booking total.
 */
CREATE TABLE RescheduleRequest (
    RescheduleID       INT             AUTO_INCREMENT PRIMARY KEY,
    OriginalBookingID  INT             NOT NULL,
    -- Linked once the reschedule is approved and a new booking is created
    NewBookingID       INT             NULL,
    RequestDateTime    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    NewVoyageID        INT             NOT NULL,
    -- Computed by trigger when < 48 hours before departure
    RescheduleFee      DECIMAL(12,2)   NOT NULL DEFAULT 0,
    RequestStatus      VARCHAR(30)     NOT NULL DEFAULT 'Requested',
    Reason             VARCHAR(255),
    CONSTRAINT FK_RescheduleRequest_OriginalBooking
        FOREIGN KEY (OriginalBookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_RescheduleRequest_NewBooking
        FOREIGN KEY (NewBookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_RescheduleRequest_NewVoyage
        FOREIGN KEY (NewVoyageID) REFERENCES CruiseVoyage(VoyageID)
);

/*
 * Payment
 * Records each payment transaction against a booking.
 * TransactionReference is unique to prevent duplicate payment records.
 */
CREATE TABLE Payment (
    PaymentID             INT             AUTO_INCREMENT PRIMARY KEY,
    BookingID             INT             NOT NULL,
    PaymentDateTime       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Amount                DECIMAL(12,2)   NOT NULL,
    PaymentMethod         VARCHAR(50)     NOT NULL,
    PaymentStatus         VARCHAR(30)     NOT NULL DEFAULT 'Pending',
    TransactionReference  VARCHAR(100)    UNIQUE,
    CONSTRAINT FK_Payment_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID)
);

/* ============================================================
   SECTION 8: FUNCTION AND TRIGGERS
   ============================================================
   6 Schema Constraints (CHECK constraints in Sections 1–7):
     1. CK_Cabin_MaxOccupancy                  — enforces max 5 passengers per cabin
     2. CK_CruiseVoyage_ArrivalAfterDeparture  — arrival must be after departure
     3. CK_BookingPassenger_InfantBedOption    — valid bed options for infants
     4. CK_Booking_Status                      — restricts to valid booking states
     5. CK_CancellationPolicy_PenaltyType      — restricts to valid penalty types
     6. CK_AgeCategory_AgeRange                — ensures MinAge <= MaxAge

   6 Triggers (BEFORE/AFTER INSERT only):
     1. TR_BookingCabin_BI_PreventDoubleBooking
     2. TR_BookingPassenger_BI_ValidateRules
     3. TR_BookingBaggage_BI_ValidateLimit
     4. TR_BookingCancellation_BI_ApplyPenalty
     5. TR_BookingCancellation_AI_UpdateBookingStatus
     6. TR_BookingPassenger_AI_UpdateBookingTotal
   ============================================================ */

DELIMITER $$

/*
 * fn_CalculateAge
 * Returns the age of a person in whole years on a given reference date.
 * Used in TR_BookingPassenger_BI_ValidateRules to verify the passenger's
 * age category matches their actual age at voyage departure.
 */
CREATE FUNCTION fn_CalculateAge(DateOfBirth DATE, ReferenceDate DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    RETURN TIMESTAMPDIFF(YEAR, DateOfBirth, ReferenceDate);
END$$

/* ---------------------------------------------------------------
   Trigger 1: TR_BookingCabin_BI_PreventDoubleBooking
   Fires:  BEFORE INSERT ON BookingCabin
   Rules enforced:
     1. The cabin must belong to the ship assigned to the voyage.
     2. The same cabin cannot be booked twice on the same voyage.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCabin_BI_PreventDoubleBooking
BEFORE INSERT ON BookingCabin
FOR EACH ROW
BEGIN
    DECLARE v_BookingShipID INT;
    DECLARE v_CabinShipID   INT;

    SELECT v.ShipID INTO v_BookingShipID
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE b.BookingID = NEW.BookingID;

    SELECT ShipID INTO v_CabinShipID FROM Cabin WHERE CabinID = NEW.CabinID;

    IF v_BookingShipID <> v_CabinShipID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cabin must belong to the ship assigned to the booked voyage.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM BookingCabin bc
        INNER JOIN Booking b  ON bc.BookingID = b.BookingID
        INNER JOIN Booking nb ON NEW.BookingID = nb.BookingID
        WHERE bc.CabinID = NEW.CabinID
          AND b.VoyageID = nb.VoyageID
          AND b.BookingStatus  IN ('Pending', 'Confirmed')
          AND nb.BookingStatus IN ('Pending', 'Confirmed')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This cabin is already booked for the same voyage.';
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger 2: TR_BookingPassenger_BI_ValidateRules
   Fires:  BEFORE INSERT ON BookingPassenger
   Rules enforced:
     1. BookingCabin must belong to the same booking.
     2. Cabin occupancy must not exceed MaxOccupancy or 5.
     3. Passenger age category must match actual age at departure.
     4. InfantBedOption must be SharedBed/Cot for infants, NotApplicable otherwise.
     5. Chaperoned Youth: ages 15–17 only, operator must support programme.
     6. Minors (age ≤ 17) need an adult guardian in same or adjacent cabin.
     7. Sets DailySupervisionFee for Chaperoned Youth passengers.
     8. Computes FinalFare (infant %, or base fare from FareRule).
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingPassenger_BI_ValidateRules
BEFORE INSERT ON BookingPassenger
FOR EACH ROW
BEGIN
    DECLARE v_CabinBookingID  INT;
    DECLARE v_MaxOccupancy    INT;
    DECLARE v_OccupancyCount  INT;
    DECLARE v_PassengerAge    INT;
    DECLARE v_CategoryMin     INT;
    DECLARE v_CategoryMax     INT;
    DECLARE v_CategoryName    VARCHAR(30);
    DECLARE v_AllowsYouth     BOOLEAN;
    DECLARE v_HasGuardian     INT DEFAULT 0;
    DECLARE v_FareRuleID      INT;
    DECLARE v_BaseFare        DECIMAL(12,2);
    DECLARE v_AdultFare       DECIMAL(12,2);
    DECLARE v_ChildFare       DECIMAL(12,2);
    DECLARE v_SupervisionFee  DECIMAL(10,2);

    -- Step 1: BookingCabin must belong to this booking
    SELECT bc.BookingID, c.MaxOccupancy
    INTO v_CabinBookingID, v_MaxOccupancy
    FROM BookingCabin bc
    INNER JOIN Cabin c ON bc.CabinID = c.CabinID
    WHERE bc.BookingCabinID = NEW.BookingCabinID;

    IF v_CabinBookingID <> NEW.BookingID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BookingPassenger.BookingID must match BookingCabin.BookingID.';
    END IF;

    -- Step 2: max occupancy (hard cap of 5)
    SELECT COUNT(*) INTO v_OccupancyCount
    FROM BookingPassenger WHERE BookingCabinID = NEW.BookingCabinID;

    IF v_OccupancyCount + 1 > v_MaxOccupancy OR v_OccupancyCount + 1 > 5 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A cabin can contain a maximum of 5 passengers only.';
    END IF;

    -- Step 3: age category must match actual age at voyage departure
    SELECT fn_CalculateAge(p.DateOfBirth, DATE(v.DepartureDateTime)),
           ac.MinAge, ac.MaxAge, ac.CategoryName, co.AllowsChaperonedYouth
    INTO v_PassengerAge, v_CategoryMin, v_CategoryMax, v_CategoryName, v_AllowsYouth
    FROM Passenger p
    INNER JOIN Booking b         ON b.BookingID     = NEW.BookingID
    INNER JOIN CruiseVoyage v    ON b.VoyageID       = v.VoyageID
    INNER JOIN CruiseShip s      ON v.ShipID         = s.ShipID
    INNER JOIN CruiseOperator co ON s.OperatorID     = co.OperatorID
    INNER JOIN AgeCategory ac    ON ac.AgeCategoryID = NEW.AgeCategoryID
    WHERE p.PassengerID = NEW.PassengerID;

    IF v_PassengerAge < v_CategoryMin
       OR (v_CategoryMax IS NOT NULL AND v_PassengerAge > v_CategoryMax) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Passenger age category must match the passenger age at voyage departure.';
    END IF;

    -- Step 4: InfantBedOption validation
    IF v_CategoryName = 'Infant' AND NEW.InfantBedOption NOT IN ('SharedBed', 'Cot') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Infant passengers must have either SharedBed or Cot as InfantBedOption.';
    END IF;

    IF v_CategoryName <> 'Infant' AND NEW.InfantBedOption <> 'NotApplicable' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'InfantBedOption must be NotApplicable for non-infant passengers.';
    END IF;

    -- Step 5: Chaperoned Youth eligibility
    IF NEW.IsChaperonedYouth = TRUE
       AND (v_AllowsYouth = FALSE OR v_CategoryName <> 'Teen' OR v_PassengerAge NOT BETWEEN 15 AND 17) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Chaperoned Youth is only allowed for age 15 to 17 when the operator supports the program.';
    END IF;

    -- Step 6: minors need adult guardian in same or adjacent cabin
    IF v_PassengerAge <= 17 AND NEW.IsChaperonedYouth = FALSE THEN
        SELECT COUNT(*) INTO v_HasGuardian
        FROM BookingPassenger bp
        INNER JOIN AgeCategory ac ON bp.AgeCategoryID = ac.AgeCategoryID
        WHERE bp.BookingID = NEW.BookingID AND bp.BookingCabinID = NEW.BookingCabinID
          AND ac.MinAge >= 18;

        IF v_HasGuardian = 0 THEN
            SELECT COUNT(*) INTO v_HasGuardian
            FROM BookingPassenger   guardian_bp
            INNER JOIN AgeCategory  guardian_ac ON guardian_bp.AgeCategoryID  = guardian_ac.AgeCategoryID
            INNER JOIN BookingCabin guardian_bc ON guardian_bp.BookingCabinID = guardian_bc.BookingCabinID
            INNER JOIN Booking      guardian_b  ON guardian_bc.BookingID      = guardian_b.BookingID
            INNER JOIN BookingCabin teen_bc     ON teen_bc.BookingCabinID     = NEW.BookingCabinID
            INNER JOIN CabinAdjacency ca        ON ca.CabinID       = teen_bc.CabinID
                                               AND ca.AdjacentCabinID = guardian_bc.CabinID
            INNER JOIN Booking      teen_b      ON teen_b.BookingID = NEW.BookingID
            WHERE guardian_b.VoyageID = teen_b.VoyageID
              AND guardian_b.BookingStatus IN ('Pending', 'Confirmed')
              AND guardian_ac.MinAge >= 18;
        END IF;

        IF v_HasGuardian = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Passengers aged 17 or below require an adult in the same or adjacent cabin unless approved for Chaperoned Youth.';
        END IF;
    END IF;

    -- Step 7: supervision fee for Chaperoned Youth
    IF NEW.IsChaperonedYouth = TRUE THEN
        SELECT COALESCE(MAX(Fee), 0) INTO v_SupervisionFee
        FROM SpecialService WHERE ServiceType = 'Chaperoned Youth';
        SET NEW.DailySupervisionFee = v_SupervisionFee;
    ELSE
        SET NEW.DailySupervisionFee = 0;
    END IF;

    -- Step 8: compute FinalFare
    IF v_CategoryName = 'Infant' THEN
        SELECT fr.BaseFare INTO v_AdultFare
        FROM FareRule fr
        INNER JOIN Booking b       ON b.BookingID        = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID  = NEW.BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID          = bc.CabinID
        INNER JOIN AgeCategory ac  ON ac.AgeCategoryID   = fr.AgeCategoryID
        WHERE fr.VoyageID = b.VoyageID AND fr.CabinCategoryID = c.CabinCategoryID
          AND ac.CategoryName = 'Adult'
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC LIMIT 1;

        IF v_AdultFare IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Adult fare rule is required to calculate SharedBed infant fare.';
        END IF;

        SELECT fr.BaseFare INTO v_ChildFare
        FROM FareRule fr
        INNER JOIN Booking b       ON b.BookingID        = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID  = NEW.BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID          = bc.CabinID
        INNER JOIN AgeCategory ac  ON ac.AgeCategoryID   = fr.AgeCategoryID
        WHERE fr.VoyageID = b.VoyageID AND fr.CabinCategoryID = c.CabinCategoryID
          AND ac.CategoryName = 'Child'
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC LIMIT 1;

        IF v_ChildFare IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Child fare rule is required to calculate Cot infant fare.';
        END IF;

        SET NEW.FareRuleID = NULL;
        SET NEW.FinalFare  = IF(NEW.InfantBedOption = 'SharedBed', v_AdultFare * 0.15, v_ChildFare * 0.50);

    ELSE
        SELECT fr.FareRuleID, fr.BaseFare INTO v_FareRuleID, v_BaseFare
        FROM FareRule fr
        INNER JOIN Booking b       ON b.BookingID        = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID  = NEW.BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID          = bc.CabinID
        WHERE fr.VoyageID = b.VoyageID AND fr.CabinCategoryID = c.CabinCategoryID
          AND fr.AgeCategoryID = NEW.AgeCategoryID
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC LIMIT 1;

        IF v_BaseFare IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Fare rule is required for this voyage, cabin category, and age category.';
        END IF;

        SET NEW.FareRuleID = v_FareRuleID;
        SET NEW.FinalFare  = v_BaseFare;
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger 3: TR_BookingBaggage_BI_ValidateLimit
   Fires:  BEFORE INSERT ON BookingBaggage
   Rule enforced: automatically sets IsOverLimit by comparing
   the declared WeightKG against the voyage BaggageWeightLimitKG.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingBaggage_BI_ValidateLimit
BEFORE INSERT ON BookingBaggage
FOR EACH ROW
BEGIN
    DECLARE v_AllowedWeight DECIMAL(6,2);
    SELECT v.BaggageWeightLimitKG INTO v_AllowedWeight
    FROM BookingPassenger bp
    INNER JOIN Booking b      ON bp.BookingID = b.BookingID
    INNER JOIN CruiseVoyage v ON b.VoyageID   = v.VoyageID
    WHERE bp.BookingPassengerID = NEW.BookingPassengerID;
    SET NEW.IsOverLimit = NEW.WeightKG > v_AllowedWeight;
END$$

/* ---------------------------------------------------------------
   Trigger 4: TR_BookingCancellation_BI_ApplyPenalty
   Fires:  BEFORE INSERT ON BookingCancellation
   Rule enforced: computes PenaltyAmount and RefundAmount based on
   the operator's CancellationPolicy and hours until departure.
   Business rule: cancellation < 48 hours before departure → full forfeit.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCancellation_BI_ApplyPenalty
BEFORE INSERT ON BookingCancellation
FOR EACH ROW
BEGIN
    DECLARE v_DepartureTime DATETIME;
    DECLARE v_BookingTotal  DECIMAL(12,2);
    DECLARE v_HoursUntil    INT;
    DECLARE v_PenaltyType   VARCHAR(30);
    DECLARE v_PenaltyValue  DECIMAL(10,2);

    SELECT v.DepartureDateTime, b.TotalAmount, cp.PenaltyType, cp.PenaltyValue
    INTO v_DepartureTime, v_BookingTotal, v_PenaltyType, v_PenaltyValue
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    INNER JOIN CruiseShip s   ON v.ShipID   = s.ShipID
    LEFT JOIN CancellationPolicy cp
        ON s.OperatorID = cp.OperatorID
       AND cp.HoursBeforeDeparture >= TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, v.DepartureDateTime)
    WHERE b.BookingID = NEW.BookingID
    ORDER BY cp.HoursBeforeDeparture ASC
    LIMIT 1;

    SET v_HoursUntil = TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, v_DepartureTime);

    IF v_HoursUntil <= 48 AND v_PenaltyType = 'FullForfeit' THEN
        SET NEW.PenaltyAmount = v_BookingTotal;
        SET NEW.RefundAmount  = 0;
    ELSEIF v_PenaltyType = 'Percentage' THEN
        SET NEW.PenaltyAmount = v_BookingTotal * (v_PenaltyValue / 100);
        SET NEW.RefundAmount  = v_BookingTotal - NEW.PenaltyAmount;
    ELSEIF v_PenaltyType = 'FixedAmount' THEN
        SET NEW.PenaltyAmount = LEAST(v_PenaltyValue, v_BookingTotal);
        SET NEW.RefundAmount  = v_BookingTotal - NEW.PenaltyAmount;
    ELSE
        SET NEW.PenaltyAmount = 0;
        SET NEW.RefundAmount  = v_BookingTotal;
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger 5: TR_BookingCancellation_AI_UpdateBookingStatus
   Fires:  AFTER INSERT ON BookingCancellation
   Rule enforced: marks the associated booking as 'Cancelled'
   immediately after a cancellation record is inserted.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCancellation_AI_UpdateBookingStatus
AFTER INSERT ON BookingCancellation
FOR EACH ROW
BEGIN
    UPDATE Booking SET BookingStatus = 'Cancelled' WHERE BookingID = NEW.BookingID;
END$$

/* ---------------------------------------------------------------
   Trigger 6: TR_BookingPassenger_AI_UpdateBookingTotal
   Fires:  AFTER INSERT ON BookingPassenger
   Rule enforced: recalculates Booking.TotalAmount as the sum of
   all FinalFare values after each passenger is added.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingPassenger_AI_UpdateBookingTotal
AFTER INSERT ON BookingPassenger
FOR EACH ROW
BEGIN
    UPDATE Booking
    SET TotalAmount = (SELECT COALESCE(SUM(FinalFare), 0)
                       FROM BookingPassenger WHERE BookingID = NEW.BookingID)
    WHERE BookingID = NEW.BookingID;
END$$

DELIMITER ;


/* ============================================================
   SECTION 9: SEED DATA
   ============================================================ */

-- Cabin categories (the four permitted types in GLCL)
INSERT INTO CabinCategory (CategoryName, CategoryDescription)
VALUES
('Interior',   'Inside cabin without sea view.'),
('Ocean View', 'Cabin with sea-facing window.'),
('Balcony',    'Cabin with private balcony.'),
('Suite',      'Premium suite with luxury facilities.');

-- Age categories (AgeCategoryID: 1=Infant, 2=Child, 3=Teen, 4=Adult, 5=Senior)
INSERT INTO AgeCategory (CategoryName, MinAge, MaxAge)
VALUES
('Infant', 0,  1),
('Child',  2,  12),
('Teen',   13, 17),
('Adult',  18, 59),
('Senior', 60, NULL);  -- no upper age bound for seniors

-- Dining options
INSERT INTO DiningOption (DiningName)
VALUES
('Fixed-time dining'),
('Flexible dining'),
('Specialty restaurant');

-- Meal package types
INSERT INTO VoyageMealPackageType (PackageName)
VALUES
('Standard boarding meal'),
('Multi-day all-inclusive dining package');

/*
 * Meal package rules:
 *   Rule 1 (MealPackageTypeID=1): 1-day voyages → standard boarding meal
 *   Rule 2 (MealPackageTypeID=2): 2+ day voyages → all-inclusive package
 */
INSERT INTO VoyageMealPackageRule (MealPackageTypeID, MinVoyageLengthDays, MaxVoyageLengthDays)
VALUES
(1, 1, 1),    -- standard boarding meal: exactly 1 day
(2, 2, NULL); -- all-inclusive package:  2 days and above

-- Special services available across all operators
INSERT INTO SpecialService (ServiceName, ServiceType, AgeRestrictionMin, AgeRestrictionMax, Fee)
VALUES
('Onboard Childcare Service',           'Childcare',        2,    12,   35.00),
('Teen Exclusive Club',                 'Teen Club',         13,   17,   0.00),
('Wheelchair Accessible Cabin Request', 'Accessibility',     NULL, NULL, 0.00),
('Mobility Assistance Service',         'Mobility',          NULL, NULL, 0.00),
('Chaperoned Youth Supervision',        'Chaperoned Youth',  15,   17,   50.00);

-- Cruise operators (OperatorID: 1=GLCL, 2=Royal Oceanic)
INSERT INTO CruiseOperator (OperatorName, HeadquartersCountry, ContactEmail, AllowsChaperonedYouth)
VALUES
('Global Luxury Cruise Lines', 'Malaysia',        'reservations@glcl.example',      TRUE),
('Royal Oceanic Voyages',      'United Kingdom',  'support@royaloceanic.example',    FALSE);

-- Ships (ShipID: 1=GLCL Majesty, 2=GLCL Pearl, 3=Oceanic Star)
INSERT INTO CruiseShip (OperatorID, ShipName, TotalDecks, PassengerCapacity)
VALUES
(1, 'GLCL Majesty', 15, 3200),
(1, 'GLCL Pearl',   12, 2200),
(2, 'Oceanic Star', 14, 2800);

-- Routes (RouteID: 1=One-way, 2=Round-trip, 3=Multi-destination)
INSERT INTO CruiseRoute (RouteName, RouteType)
VALUES
('Kuala Lumpur to Singapore Repositioning',   'One-way'),
('Penang Island Luxury Loop',                 'Round-trip'),
('Langkawi, Phuket and Krabi Island Hopper', 'Multi-destination');

-- Ports (PortID: 1=Port Klang, 2=Singapore, 3=Penang, 4=Langkawi, 5=Phuket, 6=Krabi)
INSERT INTO Port (PortName, Country)
VALUES
('Port Klang',              'Malaysia'),
('Singapore Cruise Centre', 'Singapore'),
('Penang Port',             'Malaysia'),
('Langkawi Cruise Terminal','Malaysia'),
('Phuket Deep Sea Port',    'Thailand'),
('Krabi Cruise Port',       'Thailand');

/*
 * RoutePort entries:
 *   Route 1 (One-way):         Port Klang(1) → Singapore(2)
 *   Route 2 (Round-trip):      Penang(3) → Langkawi(4) → Penang(3)
 *   Route 3 (Multi-dest):      Port Klang(1) → Langkawi(4) → Phuket(5) → Krabi(6) → Port Klang(1)
 *
 *   RoutePortID sequence (auto-assigned):
 *     1=Route1/PortKlang, 2=Route1/Singapore
 *     3=Route2/Penang(dep), 4=Route2/Langkawi, 5=Route2/Penang(arr)
 *     6=Route3/PortKlang(dep), 7=Route3/Langkawi, 8=Route3/Phuket,
 *     9=Route3/Krabi, 10=Route3/PortKlang(arr)
 */
INSERT INTO RoutePort (RouteID, PortID, StopSequence, IsHomePort)
VALUES
(1, 1, 1, TRUE),
(1, 2, 2, FALSE),
(2, 3, 1, TRUE),
(2, 4, 2, FALSE),
(2, 3, 3, TRUE),
(3, 1, 1, TRUE),
(3, 4, 2, FALSE),
(3, 5, 3, FALSE),
(3, 6, 4, FALSE),
(3, 1, 5, TRUE);

/*
 * Cabins per ship:
 *   GLCL Majesty (ShipID=1): CabinID 1–5
 *   GLCL Pearl   (ShipID=2): CabinID 6–9
 *   Oceanic Star (ShipID=3): CabinID 10–13
 *
 * CabinCategoryID: 1=Interior, 2=Ocean View, 3=Balcony, 4=Suite
 */
INSERT INTO Cabin (ShipID, CabinCategoryID, CabinNumber, DeckNumber, MaxOccupancy, IsWheelchairAccessible)
VALUES
-- GLCL Majesty
(1, 1, 'I-801',  8,  4, FALSE),  -- CabinID 1
(1, 2, 'O-802',  8,  4, FALSE),  -- CabinID 2
(1, 2, 'O-803',  8,  4, FALSE),  -- CabinID 3
(1, 3, 'B-901',  9,  5, TRUE),   -- CabinID 4
(1, 4, 'S-1001', 10, 5, TRUE),   -- CabinID 5
-- GLCL Pearl
(2, 1, 'I-501',  5,  4, FALSE),  -- CabinID 6
(2, 2, 'O-502',  5,  4, FALSE),  -- CabinID 7
(2, 3, 'B-601',  6,  5, TRUE),   -- CabinID 8
(2, 4, 'S-701',  7,  5, TRUE),   -- CabinID 9
-- Oceanic Star
(3, 1, 'I-601',  6,  4, FALSE),  -- CabinID 10
(3, 2, 'O-602',  6,  4, FALSE),  -- CabinID 11
(3, 3, 'B-701',  7,  5, TRUE),   -- CabinID 12
(3, 4, 'S-801',  8,  5, TRUE);   -- CabinID 13

/*
 * CabinAdjacency: O-802 (CabinID=2) and O-803 (CabinID=3) on GLCL Majesty
 * are physically adjacent on Deck 8. Inserted bidirectionally so the
 * teen-guardian trigger query works regardless of lookup direction.
 */
INSERT INTO CabinAdjacency (CabinID, AdjacentCabinID, AdjacencyType)
VALUES
(2, 3, 'Adjacent'),
(3, 2, 'Adjacent');

-- Dining options available per ship
INSERT INTO ShipDiningOption (ShipID, DiningOptionID)
VALUES
(1, 1),  -- GLCL Majesty: Fixed-time
(1, 2),  -- GLCL Majesty: Flexible
(1, 3),  -- GLCL Majesty: Specialty
(2, 1),  -- GLCL Pearl: Fixed-time
(2, 3),  -- GLCL Pearl: Specialty
(3, 2),  -- Oceanic Star: Flexible
(3, 3);  -- Oceanic Star: Specialty

-- Specialty cuisine types (SpecialtyDiningTypeID: 1=Vegan, 2=Gluten-Free,
--   3=Halal, 4=Kosher, 5=Low-Sodium, 6=Seafood Grill)
INSERT INTO SpecialtyDiningType (TypeName, Description)
VALUES
('Vegan',        'Fully plant-based menu with no animal products.'),
('Gluten-Free',  'Dishes prepared without gluten-containing ingredients.'),
('Halal',        'Meals prepared in accordance with Islamic dietary laws.'),
('Kosher',       'Meals prepared in accordance with Jewish dietary laws.'),
('Low-Sodium',   'Heart-healthy dishes with reduced sodium content.'),
('Seafood Grill','Premium fresh seafood grilled to order.');

-- Specialty dining types offered per ship
INSERT INTO ShipSpecialtyDining (ShipID, SpecialtyDiningTypeID)
VALUES
(1, 1),  -- GLCL Majesty: Vegan
(1, 2),  -- GLCL Majesty: Gluten-Free
(1, 3),  -- GLCL Majesty: Halal
(1, 6),  -- GLCL Majesty: Seafood Grill
(2, 1),  -- GLCL Pearl: Vegan
(2, 3),  -- GLCL Pearl: Halal
(3, 2),  -- Oceanic Star: Gluten-Free
(3, 5),  -- Oceanic Star: Low-Sodium
(3, 6);  -- Oceanic Star: Seafood Grill

/*
 * Voyages (VoyageID: 1=KL→Singapore 2-day, 2=Island Hopper 8-day)
 * Both use GLCL Majesty (ShipID=1).
 * VoyageLengthDays is computed: Voyage 1 = 2 days, Voyage 2 = 8 days.
 * Both → MealPackageRuleID=2 (all-inclusive, 2+ days).
 */
INSERT INTO CruiseVoyage (ShipID, RouteID, DepartureDateTime, ArrivalDateTime, BaggageWeightLimitKG, VoyageStatus)
VALUES
(1, 1, '2026-08-01 18:00:00', '2026-08-03 08:00:00', 25.00, 'Scheduled'),  -- VoyageID=1
(1, 3, '2026-09-10 17:00:00', '2026-09-18 09:00:00', 30.00, 'Scheduled');  -- VoyageID=2

/*
 * FareRule seed data:
 *   AgeCategoryID: 2=Child, 3=Teen, 4=Adult, 5=Senior
 *   CabinCategoryID: 1=Interior, 2=Ocean View, 3=Balcony, 4=Suite
 *   Infant fares are NOT included here — they are computed by trigger.
 */
INSERT INTO FareRule (VoyageID, CabinCategoryID, AgeCategoryID, BaseFare, EffectiveFrom, EffectiveTo)
VALUES
-- Voyage 1 — Interior
(1, 1, 2,  600.00, '2026-01-01', NULL),
(1, 1, 3,  750.00, '2026-01-01', NULL),
(1, 1, 4, 1000.00, '2026-01-01', NULL),
(1, 1, 5,  850.00, '2026-01-01', NULL),
-- Voyage 1 — Ocean View
(1, 2, 2,  850.00, '2026-01-01', NULL),
(1, 2, 3, 1000.00, '2026-01-01', NULL),
(1, 2, 4, 1350.00, '2026-01-01', NULL),
(1, 2, 5, 1150.00, '2026-01-01', NULL),
-- Voyage 1 — Balcony
(1, 3, 2, 1100.00, '2026-01-01', NULL),
(1, 3, 3, 1300.00, '2026-01-01', NULL),
(1, 3, 4, 1750.00, '2026-01-01', NULL),
(1, 3, 5, 1500.00, '2026-01-01', NULL),
-- Voyage 1 — Suite
(1, 4, 2, 1800.00, '2026-01-01', NULL),
(1, 4, 3, 2100.00, '2026-01-01', NULL),
(1, 4, 4, 2800.00, '2026-01-01', NULL),
(1, 4, 5, 2500.00, '2026-01-01', NULL),
-- Voyage 2 — Interior
(2, 1, 2, 1200.00, '2026-01-01', NULL),
(2, 1, 3, 1500.00, '2026-01-01', NULL),
(2, 1, 4, 2000.00, '2026-01-01', NULL),
(2, 1, 5, 1750.00, '2026-01-01', NULL),
-- Voyage 2 — Ocean View
(2, 2, 2, 1600.00, '2026-01-01', NULL),
(2, 2, 3, 2000.00, '2026-01-01', NULL),
(2, 2, 4, 2700.00, '2026-01-01', NULL),
(2, 2, 5, 2400.00, '2026-01-01', NULL),
-- Voyage 2 — Balcony
(2, 3, 2, 1800.00, '2026-01-01', NULL),
(2, 3, 3, 2300.00, '2026-01-01', NULL),
(2, 3, 4, 3200.00, '2026-01-01', NULL),
(2, 3, 5, 2800.00, '2026-01-01', NULL),
-- Voyage 2 — Suite
(2, 4, 2, 3000.00, '2026-01-01', NULL),
(2, 4, 3, 3800.00, '2026-01-01', NULL),
(2, 4, 4, 5200.00, '2026-01-01', NULL),
(2, 4, 5, 4600.00, '2026-01-01', NULL);

-- Both voyages are 2+ days → all-inclusive package (MealPackageRuleID=2)
INSERT INTO VoyageMealPackage (VoyageID, MealPackageRuleID)
VALUES
(1, 2),
(2, 2);

-- Baggage weight limits per operator
INSERT INTO BaggageRule (OperatorID, MaxWeightKG, EffectiveFrom, EffectiveTo)
VALUES
(1, 30.00, '2026-01-01', NULL),  -- GLCL: 30 kg
(2, 25.00, '2026-01-01', NULL);  -- Royal Oceanic: 25 kg

/*
 * Excursions by port:
 *   ExcursionID 1–2: Singapore (PortID=2)
 *   ExcursionID 3–4: Langkawi  (PortID=4)
 *   ExcursionID 5–6: Phuket    (PortID=5)
 *   ExcursionID 7–8: Krabi     (PortID=6)
 */
INSERT INTO Excursion (PortID, ExcursionName, Description, DurationHours, Price)
VALUES
(2, 'Gardens by the Bay Night Tour',   'Guided evening tour of the iconic garden domes.',                  3.00,  85.00),
(2, 'Sentosa Island Beach Day',        'Full-day beach and resort experience.',                            8.00, 120.00),
(4, 'Mangrove Kayak Adventure',        'Guided kayaking through Langkawi mangrove forests.',               4.00,  75.00),
(4, 'Eagle Square & Cable Car Tour',   'Visit Eagle Square and ride the Langkawi cable car.',              5.00,  95.00),
(5, 'Phi Phi Island Snorkel Trip',     'Speedboat trip to Phi Phi Island with snorkelling.',               7.00, 110.00),
(5, 'Old Phuket Town Heritage Walk',   'Walking tour through the historic Sino-Portuguese district.',      3.00,  50.00),
(6, 'Railay Beach Longtail Boat Trip', 'Longtail boat excursion to the secluded Railay Beach.',            5.00,  90.00),
(6, 'Tiger Cave Temple Hike',          'Guided hike up 1,237 steps to the Tiger Cave Temple summit.',     4.00,  60.00);

/*
 * VoyageExcursion: excursions available on Voyage 2 (Island Hopper).
 * RoutePort references for Voyage 2 (Route 3):
 *   RoutePortID 7 = Langkawi stop  (Route 3, StopSequence 2)
 *   RoutePortID 8 = Phuket stop    (Route 3, StopSequence 3)
 *   RoutePortID 9 = Krabi stop     (Route 3, StopSequence 4)
 * Note: Singapore excursions (ExcursionID 1–2) are not on this voyage.
 */
INSERT INTO VoyageExcursion (VoyageID, RoutePortID, ExcursionID, AvailableSlots)
VALUES
(2, 7, 3, 30),   -- Langkawi: Mangrove Kayak
(2, 7, 4, 40),   -- Langkawi: Eagle Square
(2, 8, 5, 25),   -- Phuket:   Phi Phi Snorkel
(2, 8, 6, 50),   -- Phuket:   Old Town Walk
(2, 9, 7, 35),   -- Krabi:    Railay Beach
(2, 9, 8, 45);   -- Krabi:    Tiger Cave Hike

-- Cancellation policies: full forfeit within 48 hours for both operators
INSERT INTO CancellationPolicy (OperatorID, HoursBeforeDeparture, PenaltyType, PenaltyValue)
VALUES
(1, 48, 'FullForfeit', 100.00),
(2, 48, 'FullForfeit', 100.00);

/* ============================================================
   SECTION 10: REPORTING VIEWS
   ============================================================ */

/*
 * vw_BookingPassengerDetails
 * Flat view combining booking, voyage, cabin, passenger, and fare
 * information. Intended for reservation summary reports.
 */
CREATE VIEW vw_BookingPassengerDetails AS
SELECT
    b.BookingID,
    b.BookingDate,
    b.BookingStatus,
    v.VoyageID,
    r.RouteName,
    r.RouteType,
    s.ShipName,
    c.CabinNumber,
    cc.CategoryName                                                  AS CabinCategory,
    p.PassengerID,
    p.FullName,
    p.PassportNo,
    fn_CalculateAge(p.DateOfBirth, DATE(v.DepartureDateTime))        AS AgeAtDeparture,
    ac.CategoryName                                                  AS AgeCategory,
    bp.InfantBedOption,
    bp.IsChaperonedYouth,
    bp.FinalFare
FROM BookingPassenger bp
INNER JOIN Booking       b   ON bp.BookingID      = b.BookingID
INNER JOIN CruiseVoyage  v   ON b.VoyageID        = v.VoyageID
INNER JOIN CruiseRoute   r   ON v.RouteID         = r.RouteID
INNER JOIN CruiseShip    s   ON v.ShipID          = s.ShipID
INNER JOIN BookingCabin  bc  ON bp.BookingCabinID = bc.BookingCabinID
INNER JOIN Cabin         c   ON bc.CabinID        = c.CabinID
INNER JOIN CabinCategory cc  ON c.CabinCategoryID = cc.CabinCategoryID
INNER JOIN Passenger     p   ON bp.PassengerID    = p.PassengerID
INNER JOIN AgeCategory   ac  ON bp.AgeCategoryID  = ac.AgeCategoryID;

/*
 * vw_VoyageCabinAvailability
 * Shows every cabin on every voyage with a computed availability status.
 * 'Booked'    = cabin has a Pending or Confirmed booking on this voyage.
 * 'Available' = cabin is free for this voyage.
 */
CREATE VIEW vw_VoyageCabinAvailability AS
SELECT
    v.VoyageID,
    s.ShipName,
    r.RouteName,
    c.CabinID,
    c.CabinNumber,
    cc.CategoryName AS CabinCategory,
    c.MaxOccupancy,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM BookingCabin bc
            INNER JOIN Booking b ON bc.BookingID = b.BookingID
            WHERE b.VoyageID = v.VoyageID
              AND bc.CabinID = c.CabinID
              AND b.BookingStatus IN ('Pending', 'Confirmed')
        ) THEN 'Booked'
        ELSE 'Available'
    END AS AvailabilityStatus
FROM CruiseVoyage   v
INNER JOIN CruiseShip    s  ON v.ShipID          = s.ShipID
INNER JOIN CruiseRoute   r  ON v.RouteID         = r.RouteID
INNER JOIN Cabin         c  ON s.ShipID          = c.ShipID
INNER JOIN CabinCategory cc ON c.CabinCategoryID = cc.CabinCategoryID;

SELECT 'GLCL_DB MySQL database created successfully.' AS Message;

/* ============================================================
   SECTION 11: TEST DATA
   ============================================================
   Scenarios:
     Voyage 1 (VoyageID=1): KL→Singapore, 2-day, GLCL Majesty
       Booking 1 — Interior   — 2 Adults          (Ahmad, Nurul Hana)
       Booking 2 — Balcony    — 2 Seniors          (James, Margaret) + wheelchair/mobility services
       Booking 3 — Suite      — 2 Adults + Infant SharedBed (Rajesh, Priya, Emma)
       Booking 4 — OV pair    — Adult guardian in O-803 (Sarah) + Teen in O-802 (Kevin, adjacent)

     Voyage 2 (VoyageID=2): Island Hopper, 8-day, GLCL Majesty
       Booking 5 — Interior   — 2 Adults + Child + Infant Cot (Hafiz, Christine, Lucas, Sophie)
       Booking 6 — Balcony    — 2 Seniors          (Elena, Roberto) + excursion bookings
       Booking 7 — Suite      — Adult + Chaperoned Youth Teen (Daniel, Zara)
       Booking 8 — Ocean View — 2 Adults + Child   (Lim, Siti, Ryan) → CANCELLED < 48 h (FullForfeit)

   Trigger behaviour (automatic — no manual values needed):
     TR_BookingPassenger_BI_ValidateRules        sets FinalFare, FareRuleID, DailySupervisionFee
     TR_BookingPassenger_AI_UpdateBookingTotal   updates Booking.TotalAmount after each insert
     TR_BookingBaggage_BI_ValidateLimit          sets IsOverLimit
     TR_BookingCancellation_BI_ApplyPenalty      sets PenaltyAmount, RefundAmount
     TR_BookingCancellation_AI_UpdateBookingStatus sets Booking.BookingStatus = 'Cancelled'

   Seed data cross-reference:
     AgeCategoryID  : 1=Infant  2=Child  3=Teen  4=Adult  5=Senior
     CabinCategoryID: 1=Interior  2=Ocean View  3=Balcony  4=Suite
     ServiceID      : 1=Childcare  2=Teen Club  3=Wheelchair  4=Mobility  5=Chaperoned Youth
     CabinID (Majesty): 1=I-801  2=O-802  3=O-803  4=B-901  5=S-1001
     VoyageExcursionID: 1=Langkawi Kayak  2=Langkawi Eagle  3=Phuket PhiPhi
                        4=Phuket OldTown  5=Krabi Railay    6=Krabi TigerCave
   ============================================================ */

/* ============================================================
   PASSENGER  (PassengerID 1–20)
   Ages shown are calculated at each passenger's voyage departure date.
   ============================================================ */

INSERT INTO Passenger
    (FullName, DateOfBirth, PassportNo, Nationality, Gender, ContactNo, Email)
VALUES
-- Voyage 1 — Booking 1: Interior, 2 Adults
('Ahmad Razif Hassan',  '1985-03-15', 'MY001A2345', 'Malaysian', 'Male',   '+60-12-345-6789',   'ahmad.razif@email.com'),        -- PassengerID=1,  Adult  age 41
('Nurul Hana Yusof',   '1987-07-22', 'MY002B3456', 'Malaysian', 'Female', '+60-11-456-7890',   'nurulhana.yusof@email.com'),     -- PassengerID=2,  Adult  age 39

-- Voyage 1 — Booking 2: Balcony, 2 Seniors
('James Whitmore',      '1958-04-10', 'GB003C4567', 'British',   'Male',   '+44-20-7890-1234',  'james.whitmore@email.com'),      -- PassengerID=3,  Senior age 68
('Margaret Whitmore',   '1960-11-05', 'GB004D5678', 'British',   'Female', '+44-20-7890-5678',  'margaret.whitmore@email.com'),   -- PassengerID=4,  Senior age 65

-- Voyage 1 — Booking 3: Suite, 2 Adults + 1 Infant (SharedBed)
('Rajesh Nair',         '1980-12-01', 'IN005E6789', 'Indian',    'Male',   '+91-98-7654-3210',  'rajesh.nair@email.com'),         -- PassengerID=5,  Adult  age 45
('Priya Nair',          '1983-08-25', 'IN006F7890', 'Indian',    'Female', '+91-98-8765-4321',  'priya.nair@email.com'),          -- PassengerID=6,  Adult  age 42
('Emma Nair',           '2025-05-20', 'IN007G8901', 'Indian',    'Female', NULL,                NULL),                            -- PassengerID=7,  Infant age 1

-- Voyage 1 — Booking 4: Ocean View pair — adult guardian + teen (adjacent cabin)
('Sarah Chen',          '1975-10-05', 'MY008H9012', 'Malaysian', 'Female', '+60-16-789-0123',   'sarah.chen@email.com'),          -- PassengerID=8,  Adult  age 50
('Kevin Tan',           '2009-03-12', 'MY009I0123', 'Malaysian', 'Male',   '+60-16-890-1234',   'kevin.tan@email.com'),           -- PassengerID=9,  Teen   age 17

-- Voyage 2 — Booking 8: Ocean View (cancelled < 48 h)
('Lim Wei Jian',        '1990-02-28', 'MY010J1234', 'Malaysian', 'Male',   '+60-12-901-2345',   'lim.weijian@email.com'),         -- PassengerID=10, Adult  age 36
('Siti Aishah Malik',   '1992-06-14', 'MY011K2345', 'Malaysian', 'Female', '+60-11-012-3456',   'siti.aishah@email.com'),         -- PassengerID=11, Adult  age 34
('Ryan Lim',            '2016-09-03', 'MY012L3456', 'Malaysian', 'Male',   NULL,                NULL),                            -- PassengerID=12, Child  age 10

-- Voyage 2 — Booking 5: Interior, 2 Adults + Child + Infant (Cot)
('Hafiz Omar',          '1978-06-30', 'MY013M4567', 'Malaysian', 'Male',   '+60-17-123-4567',   'hafiz.omar@email.com'),          -- PassengerID=13, Adult  age 48
('Christine Dupont',    '1995-04-02', 'FR014N5678', 'French',    'Female', '+33-6-12-34-56-78', 'christine.dupont@email.com'),    -- PassengerID=14, Adult  age 31
('Lucas Dupont',        '2018-07-15', 'FR015O6789', 'French',    'Male',   NULL,                NULL),                            -- PassengerID=15, Child  age 8
('Sophie Dupont',       '2025-09-01', 'FR016P7890', 'French',    'Female', NULL,                NULL),                            -- PassengerID=16, Infant age 1

-- Voyage 2 — Booking 6: Balcony, 2 Seniors
('Elena Marchetti',     '1960-02-14', 'IT017Q8901', 'Italian',   'Female', '+39-06-789-0123',   'elena.marchetti@email.com'),     -- PassengerID=17, Senior age 66
('Roberto Marchetti',   '1958-08-20', 'IT018R9012', 'Italian',   'Male',   '+39-06-890-1234',   'roberto.marchetti@email.com'),   -- PassengerID=18, Senior age 68

-- Voyage 2 — Booking 7: Suite, Adult + Chaperoned Youth Teen
('Zara Abdullah',       '2010-11-15', 'MY019S0123', 'Malaysian', 'Female', NULL,                'zara.guardian@email.com'),       -- PassengerID=19, Teen   age 15
('Daniel Wong',         '1988-04-22', 'MY020T1234', 'Malaysian', 'Male',   '+60-13-234-5678',   'daniel.wong@email.com');         -- PassengerID=20, Adult  age 38


/* ============================================================
   BOOKING  (BookingID 1–8)
   TotalAmount is hardcoded to match the sum of all FinalFare values
   per booking (TR_BookingPassenger_AI_UpdateBookingTotal also
   recomputes this automatically when triggers are active).
   ============================================================ */

INSERT INTO Booking
    (BookingDate, CustomerPassengerID, VoyageID, BookingStatus, TotalAmount, OriginalBookingID)
VALUES
-- Voyage 1 bookings (GLCL Majesty, departure 2026-08-01)
('2026-06-10 10:00:00', 1,  1, 'Confirmed',  2000.00, NULL),  -- BookingID=1  Ahmad    → Interior  (2×1 000.00)
('2026-06-12 11:00:00', 3,  1, 'Pending',    3000.00, NULL),  -- BookingID=2  James    → Balcony   (2×1 500.00)  awaiting confirmation
('2026-06-15 14:00:00', 5,  1, 'Confirmed',  6020.00, NULL),  -- BookingID=3  Rajesh   → Suite     (2×2 800.00 + 420.00)
('2026-06-20 09:30:00', 8,  1, 'Confirmed',  2350.00, NULL),  -- BookingID=4  Sarah    → OV pair   (1 350.00 + 1 000.00)
-- Voyage 2 bookings (GLCL Majesty, departure 2026-09-10)
('2026-07-01 08:00:00', 13, 2, 'Confirmed',  5800.00, NULL),  -- BookingID=5  Hafiz    → Interior  (2×2 000.00 + 1 200.00 + 600.00)
('2026-07-05 13:00:00', 17, 2, 'Completed',  5600.00, NULL),  -- BookingID=6  Elena    → Balcony   (2×2 800.00)  voyage completed
('2026-07-10 15:00:00', 20, 2, 'Confirmed',  9000.00, NULL),  -- BookingID=7  Daniel   → Suite     (5 200.00 + 3 800.00)
('2026-07-20 10:00:00', 10, 2, 'Confirmed',  7000.00, NULL);  -- BookingID=8  Lim      → OV        (2×2 700.00 + 1 600.00) → cancelled


/* ============================================================
   BOOKING CABIN  (BookingCabinID 1–9)
   TR_BookingCabin_BI_PreventDoubleBooking enforces:
     (a) cabin must belong to the voyage's ship
     (b) same cabin cannot appear twice on the same voyage
   The same CabinIDs recur across Voyage 1 and Voyage 2 because
   they share GLCL Majesty (ShipID=1); different voyages, no conflict.
   ============================================================ */

INSERT INTO BookingCabin
    (BookingID, CabinID, CabinPrice)
VALUES
-- Voyage 1
(1, 1, 0),   -- BookingCabinID=1  Booking 1 → CabinID=1  I-801  Interior
(2, 4, 0),   -- BookingCabinID=2  Booking 2 → CabinID=4  B-901  Balcony  (wheelchair-accessible)
(3, 5, 0),   -- BookingCabinID=3  Booking 3 → CabinID=5  S-1001 Suite    (wheelchair-accessible)
(4, 3, 0),   -- BookingCabinID=4  Booking 4 → CabinID=3  O-803  OceanView (Sarah — guardian cabin)
(4, 2, 0),   -- BookingCabinID=5  Booking 4 → CabinID=2  O-802  OceanView (Kevin  — teen cabin, adjacent to O-803)
-- Voyage 2
(5, 1, 0),   -- BookingCabinID=6  Booking 5 → CabinID=1  I-801  Interior
(6, 4, 0),   -- BookingCabinID=7  Booking 6 → CabinID=4  B-901  Balcony
(7, 5, 0),   -- BookingCabinID=8  Booking 7 → CabinID=5  S-1001 Suite
(8, 2, 0);   -- BookingCabinID=9  Booking 8 → CabinID=2  O-802  OceanView (cancelled booking)


/* ============================================================
   BOOKING PASSENGER  (BookingPassengerID 1–20)
   INSERT ORDER IS CRITICAL within each booking:
     Adults must be inserted before minors/infants in the same cabin.
     Step 6 of TR_BookingPassenger_BI_ValidateRules queries existing
     rows for an adult guardian when PassengerAge <= 17.
   Special cases:
     Booking 3 — adults (BPID 5,6) before infant (BPID 7)
     Booking 4 — Sarah in O-803 (BPID 8) before Kevin in O-802 (BPID 9)
                 so the adjacent-cabin guardian lookup succeeds
     Booking 5 — adults (BPID 10,11) before child (BPID 12) and infant (BPID 13)
     Booking 7 — Daniel (BPID 16) before Zara (BPID 17)
     Booking 8 — adults (BPID 18,19) before child (BPID 20)
   FinalFare and FareRuleID are hardcoded below (trigger also computes
   them automatically when active; these values serve as the fallback).
   AgeCategoryID: 1=Infant  2=Child  3=Teen  4=Adult  5=Senior
   FareRuleID reference (auto-assigned in FareRule insert order):
     V1 Interior : Child=1  Teen=2  Adult=3  Senior=4
     V1 OceanView: Child=5  Teen=6  Adult=7  Senior=8
     V1 Balcony  : Child=9  Teen=10 Adult=11 Senior=12
     V1 Suite    : Child=13 Teen=14 Adult=15 Senior=16
     V2 Interior : Child=17 Teen=18 Adult=19 Senior=20
     V2 OceanView: Child=21 Teen=22 Adult=23 Senior=24
     V2 Balcony  : Child=25 Teen=26 Adult=27 Senior=28
     V2 Suite    : Child=29 Teen=30 Adult=31 Senior=32
   ============================================================ */

INSERT INTO BookingPassenger
    (BookingID, BookingCabinID, PassengerID, AgeCategoryID, FareRuleID,
     InfantBedOption, IsChaperonedYouth, DailySupervisionFee, FinalFare)
VALUES
/* --- Booking 1: Interior (CabinCategoryID=1), Voyage 1 — 2 Adults ------------------- */
/* Adult Interior Voyage 1 = FareRuleID=3, BaseFare=1 000.00                             */
(1, 1, 1,  4,  3, 'NotApplicable', FALSE,  0.00, 1000.00),  -- BPID=1   Ahmad      Adult
(1, 1, 2,  4,  3, 'NotApplicable', FALSE,  0.00, 1000.00),  -- BPID=2   Nurul Hana Adult

/* --- Booking 2: Balcony (CabinCategoryID=3), Voyage 1 — 2 Seniors ------------------- */
/* Senior Balcony Voyage 1 = FareRuleID=12, BaseFare=1 500.00                            */
(2, 2, 3,  5, 12, 'NotApplicable', FALSE,  0.00, 1500.00),  -- BPID=3   James      Senior
(2, 2, 4,  5, 12, 'NotApplicable', FALSE,  0.00, 1500.00),  -- BPID=4   Margaret   Senior

/* --- Booking 3: Suite (CabinCategoryID=4), Voyage 1 — 2 Adults then 1 Infant -------- */
/* Adults inserted first so:                                                               */
/*   (a) Infant guardian check (Step 6) finds an adult already in the cabin               */
/*   (b) Trigger locates the Adult fare to compute 15% SharedBed infant fare              */
/* Adult Suite = FareRuleID=15, BaseFare=2 800.00                                         */
/* Infant SharedBed = 15% × 2 800.00 = 420.00; FareRuleID=NULL (derived, no rule row)   */
(3, 3, 5,  4, 15, 'NotApplicable', FALSE,  0.00, 2800.00),  -- BPID=5   Rajesh     Adult
(3, 3, 6,  4, 15, 'NotApplicable', FALSE,  0.00, 2800.00),  -- BPID=6   Priya      Adult
(3, 3, 7,  1, NULL,'SharedBed',    FALSE,  0.00,  420.00),  -- BPID=7   Emma       Infant SharedBed (15%×2800)

/* --- Booking 4: Ocean View pair, Voyage 1 — Adult guardian (O-803) then Teen (O-802)  */
/* Sarah must be inserted first so Kevin's trigger finds her in the adjacent cabin.       */
/* CabinAdjacency: (CabinID=2, AdjacentCabinID=3) satisfies the guardian check.          */
/* Adult OV = FareRuleID=7, 1 350.00 | Teen OV = FareRuleID=6, 1 000.00                 */
(4, 4, 8,  4,  7, 'NotApplicable', FALSE,  0.00, 1350.00),  -- BPID=8   Sarah      Adult  (O-803)
(4, 5, 9,  3,  6, 'NotApplicable', FALSE,  0.00, 1000.00),  -- BPID=9   Kevin      Teen   (O-802, adjacent guardian OK)

/* --- Booking 5: Interior (CabinCategoryID=1), Voyage 2 — 2 Adults, Child, Infant ---- */
/* Adults first for guardian check on both child and infant.                              */
/* Adult Interior V2 = FareRuleID=19, 2 000.00                                           */
/* Child Interior V2 = FareRuleID=17, 1 200.00                                           */
/* Infant Cot = 50% × 1 200.00 = 600.00; FareRuleID=NULL                                */
(5, 6, 13, 4, 19, 'NotApplicable', FALSE,  0.00, 2000.00),  -- BPID=10  Hafiz      Adult
(5, 6, 14, 4, 19, 'NotApplicable', FALSE,  0.00, 2000.00),  -- BPID=11  Christine  Adult
(5, 6, 15, 2, 17, 'NotApplicable', FALSE,  0.00, 1200.00),  -- BPID=12  Lucas      Child
(5, 6, 16, 1, NULL,'Cot',          FALSE,  0.00,  600.00),  -- BPID=13  Sophie     Infant Cot (50%×1200)

/* --- Booking 6: Balcony (CabinCategoryID=3), Voyage 2 — 2 Seniors ------------------- */
/* Senior Balcony Voyage 2 = FareRuleID=28, 2 800.00                                     */
(6, 7, 17, 5, 28, 'NotApplicable', FALSE,  0.00, 2800.00),  -- BPID=14  Elena      Senior
(6, 7, 18, 5, 28, 'NotApplicable', FALSE,  0.00, 2800.00),  -- BPID=15  Roberto    Senior

/* --- Booking 7: Suite (CabinCategoryID=4), Voyage 2 — Adult then Chaperoned Teen ---- */
/* IsChaperonedYouth=TRUE bypasses the guardian check (Step 6 skipped).                  */
/* Adult Suite V2 = FareRuleID=31, 5 200.00                                               */
/* Teen Suite V2  = FareRuleID=30, 3 800.00; DailySupervisionFee=50.00 (Chaperoned Youth)*/
(7, 8, 20, 4, 31, 'NotApplicable', FALSE,  0.00, 5200.00),  -- BPID=16  Daniel     Adult
(7, 8, 19, 3, 30, 'NotApplicable', TRUE,  50.00, 3800.00),  -- BPID=17  Zara       Teen   Chaperoned Youth

/* --- Booking 8: OceanView (CabinCategoryID=2), Voyage 2 — booking to be cancelled --- */
/* Adults first for child guardian check.                                                 */
/* Adult OceanView V2 = FareRuleID=23, 2 700.00                                          */
/* Child OceanView V2 = FareRuleID=21, 1 600.00                                          */
(8, 9, 10, 4, 23, 'NotApplicable', FALSE,  0.00, 2700.00),  -- BPID=18  Lim Wei Jian Adult
(8, 9, 11, 4, 23, 'NotApplicable', FALSE,  0.00, 2700.00),  -- BPID=19  Siti Aishah  Adult
(8, 9, 12, 2, 21, 'NotApplicable', FALSE,  0.00, 1600.00);  -- BPID=20  Ryan Lim     Child


/* ============================================================
   BOOKING BAGGAGE
   IsOverLimit is set automatically by TR_BookingBaggage_BI_ValidateLimit
   by comparing WeightKG against CruiseVoyage.BaggageWeightLimitKG.
     Voyage 1 limit = 25 kg  |  Voyage 2 limit = 30 kg
   ExcessFee remains 0 (computed charge handled at application layer).
   ============================================================ */

INSERT INTO BookingBaggage
    (BookingPassengerID, WeightKG, IsOverLimit, ExcessFee)
VALUES
-- Booking 1 passengers — Voyage 1 (25 kg limit)
(1,  22.00, FALSE, 0),   -- Ahmad:      22.0 kg  ✓ within limit
(2,  27.50, TRUE,  0),   -- Nurul Hana: 27.5 kg  ✗ over 25 kg limit

-- Booking 2 passengers — Voyage 1 (25 kg limit)
(3,  18.00, FALSE, 0),   -- James:      18.0 kg  ✓
(4,  20.00, FALSE, 0),   -- Margaret:   20.0 kg  ✓

-- Booking 3 passengers — Voyage 1 (25 kg limit)
(5,  24.00, FALSE, 0),   -- Rajesh:     24.0 kg  ✓
(6,  19.50, FALSE, 0),   -- Priya:      19.5 kg  ✓

-- Booking 4 passengers — Voyage 1 (25 kg limit)
(8,  26.00, TRUE,  0),   -- Sarah:      26.0 kg  ✗ over 25 kg limit
(9,  12.00, FALSE, 0),   -- Kevin:      12.0 kg  ✓

-- Booking 5 passengers — Voyage 2 (30 kg limit)
(10, 28.00, FALSE, 0),   -- Hafiz:      28.0 kg  ✓
(11, 33.50, TRUE,  0),   -- Christine:  33.5 kg  ✗ over 30 kg limit
(12,  8.50, FALSE, 0),   -- Lucas:       8.5 kg  ✓

-- Booking 6 passengers — Voyage 2 (30 kg limit)
(14, 22.00, FALSE, 0),   -- Elena:      22.0 kg  ✓
(15, 25.00, FALSE, 0),   -- Roberto:    25.0 kg  ✓

-- Booking 7 passengers — Voyage 2 (30 kg limit)
(16, 25.00, FALSE, 0),   -- Daniel:     25.0 kg  ✓
(17, 15.00, FALSE, 0),   -- Zara:       15.0 kg  ✓

-- Booking 8 passengers — Voyage 2 (30 kg limit, booking will be cancelled)
(18, 29.00, FALSE, 0),   -- Lim Wei Jian: 29.0 kg  ✓
(19, 31.00, TRUE,  0),   -- Siti Aishah:  31.0 kg  ✗ over 30 kg limit
(20, 10.00, FALSE, 0);   -- Ryan Lim:     10.0 kg  ✓


/* ============================================================
   PASSENGER SPECIAL SERVICE
   ServiceID: 1=Childcare (2–12, fee 35)
              2=Teen Club (13–17, fee 0)
              3=Wheelchair Accessible Cabin (no age limit, fee 0)
              4=Mobility Assistance (no age limit, fee 0)
              5=Chaperoned Youth Supervision (15–17, fee 50)
   ============================================================ */

INSERT INTO PassengerSpecialService
    (BookingPassengerID, ServiceID, RequestStatus, Fee)
VALUES
-- James Whitmore (BPID=3, Senior, Booking 2): wheelchair-accessible cabin
(3,  3, 'Approved',  0.00),
-- Margaret Whitmore (BPID=4, Senior, Booking 2): mobility assistance
(4,  4, 'Approved',  0.00),
-- Kevin Tan (BPID=9, Teen age 17, Booking 4): Teen Exclusive Club
(9,  2, 'Approved',  0.00),
-- Lucas Dupont (BPID=12, Child age 8, Booking 5): Onboard Childcare Service
(12, 1, 'Approved',  35.00),
-- Zara Abdullah (BPID=17, Teen age 15, Booking 7): Chaperoned Youth Supervision
(17, 5, 'Approved',  50.00),
-- Zara Abdullah (BPID=17): also enrolled in Teen Exclusive Club
(17, 2, 'Approved',  0.00),
-- Ryan Lim (BPID=20, Child age 10, Booking 8 — cancelled): Onboard Childcare
(20, 1, 'Cancelled', 35.00);


/* ============================================================
   BOOKING EXCURSION  (Voyage 2 only)
   VoyageExcursionID reference:
     1 = Langkawi  Mangrove Kayak Adventure       ( 75.00)
     2 = Langkawi  Eagle Square & Cable Car Tour  ( 95.00)
     3 = Phuket    Phi Phi Island Snorkel Trip    (110.00)
     4 = Phuket    Old Phuket Town Heritage Walk  ( 50.00)
     5 = Krabi     Railay Beach Longtail Boat     ( 90.00)
     6 = Krabi     Tiger Cave Temple Hike         ( 60.00)
   NOTE: VoyageExcursionID=6 (Tiger Cave Temple Hike) receives NO
         bookings, supporting the "excursions with no sales" query.
   ============================================================ */

INSERT INTO BookingExcursion
    (BookingPassengerID, VoyageExcursionID, BookingDateTime, ExcursionStatus, AmountPaid)
VALUES
-- Hafiz (BPID=10, Booking 5): Langkawi Mangrove Kayak + Phuket Phi Phi Snorkel
(10, 1, '2026-07-01 08:30:00', 'Booked', 75.00),
(10, 3, '2026-07-01 08:35:00', 'Booked', 110.00),
-- Christine (BPID=11, Booking 5): Langkawi Eagle Square & Cable Car
(11, 2, '2026-07-01 08:40:00', 'Booked', 95.00),
-- Elena (BPID=14, Booking 6): Phuket Old Town Heritage Walk + Krabi Railay Beach
(14, 4, '2026-07-05 13:20:00', 'Booked', 50.00),
(14, 5, '2026-07-05 13:25:00', 'Booked', 90.00),
-- Roberto (BPID=15, Booking 6): Krabi Railay Beach
(15, 5, '2026-07-05 13:30:00', 'Booked', 90.00),
-- Daniel (BPID=16, Booking 7): Langkawi Mangrove Kayak + Phuket Phi Phi Snorkel
(16, 1, '2026-07-10 15:20:00', 'Booked', 75.00),
(16, 3, '2026-07-10 15:25:00', 'Booked', 110.00);
-- VoyageExcursionID=6 (Tiger Cave Temple Hike) intentionally left with zero bookings.


/* ============================================================
   BOOKING CANCELLATION  (1 record — Booking 8)
   Booking 8 is cancelled 31 hours before Voyage 2 departure.
   Business rule (< 48 h before departure) → FullForfeit applies.

   TR_BookingCancellation_BI_ApplyPenalty computes:
     HoursUntilDeparture = TIMESTAMPDIFF(HOUR,
         '2026-09-09 10:00:00', '2026-09-10 17:00:00') = 31 h  (≤ 48)
     Policy matched: OperatorID=1, HoursBeforeDeparture=48, Type='FullForfeit'
     → PenaltyAmount = Booking.TotalAmount = 7 000.00
     → RefundAmount  = 0.00

   TR_BookingCancellation_AI_UpdateBookingStatus then sets
     Booking 8 BookingStatus = 'Cancelled'.
   ============================================================ */

INSERT INTO BookingCancellation
    (BookingID, CancellationDateTime, Reason, PenaltyAmount, RefundAmount, ProcessedBy)
VALUES
(8,
 '2026-09-09 10:00:00',
 'Passengers unable to travel due to an unforeseen medical emergency.',
 7000.00,  -- FullForfeit: 31 h before departure (< 48 h) → full TotalAmount forfeited
 0.00,     -- no refund issued
 'Reservations Team');


/* ============================================================
   RESCHEDULE REQUEST  (1 record)
   Booking 1 (Voyage 1) requests a transfer to Voyage 2.

   TR_RescheduleRequest_BI_ValidateRules validates:
     RequestDateTime '2026-07-01 10:00:00'
       < Voyage 1 departure '2026-08-01 18:00:00'           → OK (not yet departed)
     Voyage 2 departure '2026-09-10'
       < BookingDate '2026-06-10' + 1 YEAR = '2027-06-10'   → OK (within 1-year window)
     TIMESTAMPDIFF(HOUR, request, departure) = 752 h  (> 48) → RescheduleFee = 0.00

   NewBookingID = NULL: request is pending; no new booking created yet.
   ============================================================ */

INSERT INTO RescheduleRequest
    (OriginalBookingID, NewBookingID, RequestDateTime,
     NewVoyageID, RescheduleFee, RequestStatus, Reason)
VALUES
(1,
 NULL,
 '2026-07-01 10:00:00',
 2,
 0,           -- trigger confirms 0.00 (> 48 h before departure, no late-change penalty)
 'Requested',
 'Passenger wishes to extend holiday on the 8-day island-hopper itinerary.');


/* ============================================================
   PAYMENT  (PaymentID 1–8)
   Amounts match trigger-computed Booking.TotalAmount values.
   Booking 8 was paid in full before cancellation; no refund is
   issued because the FullForfeit policy applies (< 48 h cancellation).
   ============================================================ */

INSERT INTO Payment
    (BookingID, PaymentDateTime, Amount, PaymentMethod, PaymentStatus, TransactionReference)
VALUES
(1, '2026-06-10 10:15:00',  2000.00, 'Credit Card',   'Paid',    'TXN-20260610-001'),
(2, '2026-06-12 11:20:00',  3000.00, 'Bank Transfer', 'Paid',    'TXN-20260612-002'),
(3, '2026-06-15 14:30:00',  6020.00, 'Credit Card',   'Paid',    'TXN-20260615-003'),
(4, '2026-06-20 09:45:00',  2350.00, 'Debit Card',    'Paid',    'TXN-20260620-004'),
(5, '2026-07-01 08:20:00',  5800.00, 'Credit Card',   'Paid',    'TXN-20260701-005'),
(6, '2026-07-05 13:15:00',  5600.00, 'Bank Transfer', 'Paid',    'TXN-20260705-006'),
(7, '2026-07-10 15:30:00',  9000.00, 'Credit Card',   'Paid',    'TXN-20260710-007'),
(8, '2026-07-20 10:20:00',  7000.00, 'Debit Card',    'Paid',    'TXN-20260720-008');

SELECT 'GLCL_DB test data loaded successfully.' AS Message;

/* ============================================================
   SECTION 12: ADDITIONAL SAMPLE DATA — THREE NEW OPERATORS
   ============================================================
   New operators, ships, voyages, and bookings added for
   broader test coverage.  No existing rows are modified.

   ID ranges (auto-assigned, follows existing data):
     OperatorID : 3–5       ShipID      : 4–6
     CabinID    : 14–25     VoyageID    : 3–5
     FareRuleID : 33–80     PassengerID : 21–35
     BookingID  : 9–16      BookingCabinID  : 10–17
     BookingPassengerID : 21–35           PaymentID : 9–16

   Voyages 3 & 4 are set to 'Completed' (departed earlier in 2026).
   Voyage 5 is 'Scheduled' (future, November 2026).
   BookingStatus mix: 'Completed' for past voyages,
                      'Confirmed'  for Voyage 5.

   FareRuleID reference for new voyages:
     V3 Interior : Child=33 Teen=34 Adult=35 Senior=36
     V3 OceanView: Child=37 Teen=38 Adult=39 Senior=40
     V3 Balcony  : Child=41 Teen=42 Adult=43 Senior=44
     V3 Suite    : Child=45 Teen=46 Adult=47 Senior=48
     V4 Interior : Child=49 Teen=50 Adult=51 Senior=52
     V4 OceanView: Child=53 Teen=54 Adult=55 Senior=56
     V4 Balcony  : Child=57 Teen=58 Adult=59 Senior=60
     V4 Suite    : Child=61 Teen=62 Adult=63 Senior=64
     V5 Interior : Child=65 Teen=66 Adult=67 Senior=68
     V5 OceanView: Child=69 Teen=70 Adult=71 Senior=72
     V5 Balcony  : Child=73 Teen=74 Adult=75 Senior=76
     V5 Suite    : Child=77 Teen=78 Adult=79 Senior=80
   ============================================================ */

-- ----------------------------------------------------------------
-- NEW CRUISE OPERATORS  (OperatorID 3–5)
-- ----------------------------------------------------------------
INSERT INTO CruiseOperator (OperatorName, HeadquartersCountry, ContactEmail, AllowsChaperonedYouth)
VALUES
('Mediterranean Star Cruises', 'Italy',     'reservations@medstar.example',    FALSE),  -- OperatorID=3
('Pacific Dream Cruises',      'Australia', 'bookings@pacificdream.example',   TRUE),   -- OperatorID=4
('Asian Pearl Cruises',        'Singapore', 'reservations@asianpearl.example', FALSE);  -- OperatorID=5

-- ----------------------------------------------------------------
-- NEW SHIPS  (ShipID 4–6, one per new operator)
-- ----------------------------------------------------------------
INSERT INTO CruiseShip (OperatorID, ShipName, TotalDecks, PassengerCapacity)
VALUES
(3, 'MS Adriatica',      11, 2000),  -- ShipID=4
(4, 'Pacific Explorer',  13, 2600),  -- ShipID=5
(5, 'Pearl of Asia',     10, 1800);  -- ShipID=6

-- ----------------------------------------------------------------
-- NEW CABINS  (CabinID 14–25, 4 per ship)
-- CabinCategoryID: 1=Interior  2=Ocean View  3=Balcony  4=Suite
-- ----------------------------------------------------------------
INSERT INTO Cabin (ShipID, CabinCategoryID, CabinNumber, DeckNumber, MaxOccupancy, IsWheelchairAccessible)
VALUES
-- MS Adriatica (ShipID=4)
(4, 1, 'I-401',  4, 4, FALSE),   -- CabinID=14
(4, 2, 'O-501',  5, 4, FALSE),   -- CabinID=15
(4, 3, 'B-601',  6, 5, TRUE),    -- CabinID=16
(4, 4, 'S-701',  7, 5, TRUE),    -- CabinID=17
-- Pacific Explorer (ShipID=5)
(5, 1, 'I-501',  5, 4, FALSE),   -- CabinID=18
(5, 2, 'O-601',  6, 4, FALSE),   -- CabinID=19
(5, 3, 'B-701',  7, 5, TRUE),    -- CabinID=20
(5, 4, 'S-801',  8, 5, TRUE),    -- CabinID=21
-- Pearl of Asia (ShipID=6)
(6, 3, 'B-601',  6, 5, TRUE),    -- CabinID=22
(6, 1, 'I-401',  4, 4, FALSE),   -- CabinID=23
(6, 4, 'S-701',  7, 5, TRUE),    -- CabinID=24
(6, 2, 'O-501',  5, 4, FALSE);   -- CabinID=25

-- ----------------------------------------------------------------
-- DINING OPTIONS PER SHIP
-- DiningOptionID: 1=Fixed-time  2=Flexible  3=Specialty restaurant
-- ----------------------------------------------------------------
INSERT INTO ShipDiningOption (ShipID, DiningOptionID)
VALUES
(4, 1), (4, 3),          -- MS Adriatica:     Fixed-time, Specialty
(5, 2), (5, 3),          -- Pacific Explorer: Flexible, Specialty
(6, 1), (6, 2), (6, 3);  -- Pearl of Asia:    Fixed-time, Flexible, Specialty

-- SpecialtyDiningTypeID: 1=Vegan 2=Gluten-Free 3=Halal 4=Kosher 5=Low-Sodium 6=Seafood Grill
INSERT INTO ShipSpecialtyDining (ShipID, SpecialtyDiningTypeID)
VALUES
(4, 1), (4, 3),           -- MS Adriatica:     Vegan, Halal
(5, 2), (5, 6),           -- Pacific Explorer: Gluten-Free, Seafood Grill
(6, 1), (6, 3), (6, 5);  -- Pearl of Asia:    Vegan, Halal, Low-Sodium

-- ----------------------------------------------------------------
-- NEW VOYAGES  (VoyageID 3–5)
-- All reuse existing routes; VoyageLengthDays is computed (STORED).
--   Voyage 3 — Route 2 (Penang Loop),      3 days, OperatorID=3 ship
--   Voyage 4 — Route 1 (KL→Singapore),     2 days, OperatorID=4 ship
--   Voyage 5 — Route 3 (Multi-destination), 6 days, OperatorID=5 ship
-- ----------------------------------------------------------------
INSERT INTO CruiseVoyage (ShipID, RouteID, DepartureDateTime, ArrivalDateTime, BaggageWeightLimitKG, VoyageStatus)
VALUES
(4, 2, '2026-03-10 09:00:00', '2026-03-13 17:00:00', 23.00, 'Completed'),  -- VoyageID=3
(5, 1, '2026-04-15 18:00:00', '2026-04-17 08:00:00', 25.00, 'Completed'),  -- VoyageID=4
(6, 3, '2026-11-05 17:00:00', '2026-11-11 09:00:00', 28.00, 'Scheduled');  -- VoyageID=5

-- All three voyages are 2+ days → all-inclusive meal package (MealPackageRuleID=2)
INSERT INTO VoyageMealPackage (VoyageID, MealPackageRuleID)
VALUES (3, 2), (4, 2), (5, 2);

-- ----------------------------------------------------------------
-- FARE RULES  (FareRuleID 33–80)
-- Four cabin categories × four age categories per voyage.
-- Infant fares are not stored here (computed by trigger at booking time).
-- AgeCategoryID: 2=Child  3=Teen  4=Adult  5=Senior
-- ----------------------------------------------------------------
INSERT INTO FareRule (VoyageID, CabinCategoryID, AgeCategoryID, BaseFare, EffectiveFrom, EffectiveTo)
VALUES
-- Voyage 3 — Interior (Cat 1)
(3, 1, 2,  450.00, '2026-01-01', NULL),   -- FareRuleID=33
(3, 1, 3,  550.00, '2026-01-01', NULL),   -- FareRuleID=34
(3, 1, 4,  750.00, '2026-01-01', NULL),   -- FareRuleID=35
(3, 1, 5,  650.00, '2026-01-01', NULL),   -- FareRuleID=36
-- Voyage 3 — Ocean View (Cat 2)
(3, 2, 2,  600.00, '2026-01-01', NULL),   -- FareRuleID=37
(3, 2, 3,  750.00, '2026-01-01', NULL),   -- FareRuleID=38
(3, 2, 4,  950.00, '2026-01-01', NULL),   -- FareRuleID=39
(3, 2, 5,  850.00, '2026-01-01', NULL),   -- FareRuleID=40
-- Voyage 3 — Balcony (Cat 3)
(3, 3, 2,  800.00, '2026-01-01', NULL),   -- FareRuleID=41
(3, 3, 3, 1000.00, '2026-01-01', NULL),   -- FareRuleID=42
(3, 3, 4, 1300.00, '2026-01-01', NULL),   -- FareRuleID=43
(3, 3, 5, 1100.00, '2026-01-01', NULL),   -- FareRuleID=44
-- Voyage 3 — Suite (Cat 4)
(3, 4, 2, 1500.00, '2026-01-01', NULL),   -- FareRuleID=45
(3, 4, 3, 1900.00, '2026-01-01', NULL),   -- FareRuleID=46
(3, 4, 4, 2500.00, '2026-01-01', NULL),   -- FareRuleID=47
(3, 4, 5, 2200.00, '2026-01-01', NULL),   -- FareRuleID=48
-- Voyage 4 — Interior (Cat 1)
(4, 1, 2,  500.00, '2026-01-01', NULL),   -- FareRuleID=49
(4, 1, 3,  650.00, '2026-01-01', NULL),   -- FareRuleID=50
(4, 1, 4,  900.00, '2026-01-01', NULL),   -- FareRuleID=51
(4, 1, 5,  800.00, '2026-01-01', NULL),   -- FareRuleID=52
-- Voyage 4 — Ocean View (Cat 2)
(4, 2, 2,  700.00, '2026-01-01', NULL),   -- FareRuleID=53
(4, 2, 3,  900.00, '2026-01-01', NULL),   -- FareRuleID=54
(4, 2, 4, 1200.00, '2026-01-01', NULL),   -- FareRuleID=55
(4, 2, 5, 1050.00, '2026-01-01', NULL),   -- FareRuleID=56
-- Voyage 4 — Balcony (Cat 3)
(4, 3, 2,  950.00, '2026-01-01', NULL),   -- FareRuleID=57
(4, 3, 3, 1200.00, '2026-01-01', NULL),   -- FareRuleID=58
(4, 3, 4, 1600.00, '2026-01-01', NULL),   -- FareRuleID=59
(4, 3, 5, 1400.00, '2026-01-01', NULL),   -- FareRuleID=60
-- Voyage 4 — Suite (Cat 4)
(4, 4, 2, 1800.00, '2026-01-01', NULL),   -- FareRuleID=61
(4, 4, 3, 2200.00, '2026-01-01', NULL),   -- FareRuleID=62
(4, 4, 4, 3000.00, '2026-01-01', NULL),   -- FareRuleID=63
(4, 4, 5, 2600.00, '2026-01-01', NULL),   -- FareRuleID=64
-- Voyage 5 — Interior (Cat 1)
(5, 1, 2, 1000.00, '2026-01-01', NULL),   -- FareRuleID=65
(5, 1, 3, 1300.00, '2026-01-01', NULL),   -- FareRuleID=66
(5, 1, 4, 1800.00, '2026-01-01', NULL),   -- FareRuleID=67
(5, 1, 5, 1500.00, '2026-01-01', NULL),   -- FareRuleID=68
-- Voyage 5 — Ocean View (Cat 2)
(5, 2, 2, 1400.00, '2026-01-01', NULL),   -- FareRuleID=69
(5, 2, 3, 1700.00, '2026-01-01', NULL),   -- FareRuleID=70
(5, 2, 4, 2200.00, '2026-01-01', NULL),   -- FareRuleID=71
(5, 2, 5, 1900.00, '2026-01-01', NULL),   -- FareRuleID=72
-- Voyage 5 — Balcony (Cat 3)
(5, 3, 2, 1600.00, '2026-01-01', NULL),   -- FareRuleID=73
(5, 3, 3, 2000.00, '2026-01-01', NULL),   -- FareRuleID=74
(5, 3, 4, 2700.00, '2026-01-01', NULL),   -- FareRuleID=75
(5, 3, 5, 2400.00, '2026-01-01', NULL),   -- FareRuleID=76
-- Voyage 5 — Suite (Cat 4)
(5, 4, 2, 2800.00, '2026-01-01', NULL),   -- FareRuleID=77
(5, 4, 3, 3500.00, '2026-01-01', NULL),   -- FareRuleID=78
(5, 4, 4, 4800.00, '2026-01-01', NULL),   -- FareRuleID=79
(5, 4, 5, 4200.00, '2026-01-01', NULL);   -- FareRuleID=80

-- ----------------------------------------------------------------
-- BAGGAGE RULES and CANCELLATION POLICIES for new operators
-- ----------------------------------------------------------------
INSERT INTO BaggageRule (OperatorID, MaxWeightKG, EffectiveFrom, EffectiveTo)
VALUES
(3, 23.00, '2026-01-01', NULL),   -- Mediterranean Star: 23 kg
(4, 25.00, '2026-01-01', NULL),   -- Pacific Dream:      25 kg
(5, 28.00, '2026-01-01', NULL);   -- Asian Pearl:        28 kg

-- Full forfeit within 48 hours (same policy as existing operators)
INSERT INTO CancellationPolicy (OperatorID, HoursBeforeDeparture, PenaltyType, PenaltyValue)
VALUES
(3, 48, 'FullForfeit', 100.00),
(4, 48, 'FullForfeit', 100.00),
(5, 48, 'FullForfeit', 100.00);

-- ----------------------------------------------------------------
-- NEW PASSENGERS  (PassengerID 21–35)
-- Ages verified against each voyage's DepartureDateTime.
--   Voyage 3 departs 2026-03-10 | Voyage 4 departs 2026-04-15
--   Voyage 5 departs 2026-11-05
-- ----------------------------------------------------------------
INSERT INTO Passenger (FullName, DateOfBirth, PassportNo, Nationality, Gender, ContactNo, Email)
VALUES
-- Voyage 3 — Booking 9: Interior, 2 Adults
('Marco Rossi',       '1978-06-15', 'IT021A0001', 'Italian',    'Male',   '+39-06-1234-5678', 'marco.rossi@email.com'),      -- PassengerID=21, Adult age 47
('Giulia Rossi',      '1980-03-22', 'IT022B0002', 'Italian',    'Female', '+39-06-2345-6789', 'giulia.rossi@email.com'),     -- PassengerID=22, Adult age 45

-- Voyage 3 — Booking 10: Ocean View, 1 Adult + 1 Senior
('Thomas Wright',     '1970-09-01', 'GB023C0003', 'British',    'Male',   '+44-20-3456-7890', 'thomas.wright@email.com'),    -- PassengerID=23, Adult age 55
('Elizabeth Wright',  '1960-05-12', 'GB024D0004', 'British',    'Female', '+44-20-4567-8901', 'elizabeth.wright@email.com'), -- PassengerID=24, Senior age 65

-- Voyage 3 — Booking 11: Balcony, 2 Adults (completed booking)
('Chen Wei',          '1985-11-30', 'CN025E0005', 'Chinese',    'Male',   '+86-10-5678-9012', 'chen.wei@email.com'),         -- PassengerID=25, Adult age 40
('Li Mei',            '1987-04-18', 'CN026F0006', 'Chinese',    'Female', '+86-10-6789-0123', 'li.mei@email.com'),           -- PassengerID=26, Adult age 38

-- Voyage 4 — Booking 12: Interior, 2 Adults
('Jack Morrison',     '1982-08-07', 'AU027G0007', 'Australian', 'Male',   '+61-2-7890-1234',  'jack.morrison@email.com'),    -- PassengerID=27, Adult age 43
('Emily Morrison',    '1984-12-25', 'AU028H0008', 'Australian', 'Female', '+61-2-8901-2345',  'emily.morrison@email.com'),   -- PassengerID=28, Adult age 41

-- Voyage 4 — Booking 13: Ocean View, 1 Senior (completed booking)
('Robert Chen',       '1955-07-20', 'SG029I0009', 'Singaporean','Male',   '+65-9012-3456',    'robert.chen@email.com'),      -- PassengerID=29, Senior age 70

-- Voyage 5 — Booking 14: Balcony, 2 Adults
('Amir Khan',         '1976-02-14', 'SG030J0010', 'Singaporean','Male',   '+65-9123-4567',    'amir.khan@email.com'),        -- PassengerID=30, Adult age 50
('Priya Sharma',      '1979-09-03', 'SG031K0011', 'Singaporean','Female', '+65-9234-5678',    'priya.sharma@email.com'),     -- PassengerID=31, Adult age 47

-- Voyage 5 — Booking 15: Interior, 1 Adult + 1 Child
('Tan Boon Hua',      '1986-05-10', 'MY032L0012', 'Malaysian',  'Male',   '+60-12-345-6700',  'tan.boonhua@email.com'),      -- PassengerID=32, Adult age 40
('Mei Xin Tan',       '2014-08-20', 'MY033M0013', 'Malaysian',  'Female', NULL,               NULL),                         -- PassengerID=33, Child age 12

-- Voyage 5 — Booking 16: Suite, 2 Adults (confirmed)
('David Park',        '1981-03-15', 'KR034N0014', 'South Korean','Male',  '+82-2-3456-7890',  'david.park@email.com'),       -- PassengerID=34, Adult age 45
('Grace Park',        '1983-11-28', 'KR035O0015', 'South Korean','Female','+82-2-4567-8901',  'grace.park@email.com');       -- PassengerID=35, Adult age 42

-- ----------------------------------------------------------------
-- NEW BOOKINGS  (BookingID 9–16)
-- TotalAmount hardcoded to match sum of FinalFare per booking.
--   Booking  9: 750×2         =  1 500.00
--   Booking 10: 950+850        =  1 800.00
--   Booking 11: 1 300×2        =  2 600.00
--   Booking 12: 900×2          =  1 800.00
--   Booking 13: 1 050          =  1 050.00
--   Booking 14: 2 700×2        =  5 400.00
--   Booking 15: 1 800+1 000    =  2 800.00
--   Booking 16: 4 800×2        =  9 600.00
-- ----------------------------------------------------------------
INSERT INTO Booking (BookingDate, CustomerPassengerID, VoyageID, BookingStatus, TotalAmount, OriginalBookingID)
VALUES
('2026-01-15 09:00:00', 21, 3, 'Completed',  1500.00, NULL),  -- BookingID=9   Marco    → Interior  V3
('2026-01-20 14:00:00', 23, 3, 'Completed',  1800.00, NULL),  -- BookingID=10  Thomas   → OceanView V3
('2026-02-01 11:00:00', 25, 3, 'Completed',  2600.00, NULL),  -- BookingID=11  Chen Wei → Balcony   V3
('2026-02-10 10:00:00', 27, 4, 'Completed',  1800.00, NULL),  -- BookingID=12  Jack     → Interior  V4
('2026-02-15 15:00:00', 29, 4, 'Completed',  1050.00, NULL),  -- BookingID=13  Robert   → OceanView V4
('2026-07-20 08:00:00', 30, 5, 'Confirmed',  5400.00, NULL),  -- BookingID=14  Amir     → Balcony   V5
('2026-07-25 13:00:00', 32, 5, 'Confirmed',  2800.00, NULL),  -- BookingID=15  Tan      → Interior  V5
('2026-08-01 10:00:00', 34, 5, 'Confirmed',  9600.00, NULL);  -- BookingID=16  David    → Suite     V5

-- ----------------------------------------------------------------
-- NEW BOOKING CABIN  (BookingCabinID 10–17)
-- TR_BookingCabin_BI_PreventDoubleBooking verifies the cabin
-- belongs to the ship on the booked voyage.
-- ----------------------------------------------------------------
INSERT INTO BookingCabin (BookingID, CabinID, CabinPrice)
VALUES
(9,  14, 0),   -- BookingCabinID=10  Booking 9  → CabinID=14  I-401 Interior    ShipID=4 (V3)
(10, 15, 0),   -- BookingCabinID=11  Booking 10 → CabinID=15  O-501 OceanView   ShipID=4
(11, 16, 0),   -- BookingCabinID=12  Booking 11 → CabinID=16  B-601 Balcony     ShipID=4
(12, 18, 0),   -- BookingCabinID=13  Booking 12 → CabinID=18  I-501 Interior    ShipID=5 (V4)
(13, 19, 0),   -- BookingCabinID=14  Booking 13 → CabinID=19  O-601 OceanView   ShipID=5
(14, 22, 0),   -- BookingCabinID=15  Booking 14 → CabinID=22  B-601 Balcony     ShipID=6 (V5)
(15, 23, 0),   -- BookingCabinID=16  Booking 15 → CabinID=23  I-401 Interior    ShipID=6
(16, 24, 0);   -- BookingCabinID=17  Booking 16 → CabinID=24  S-701 Suite       ShipID=6

-- ----------------------------------------------------------------
-- NEW BOOKING PASSENGER  (BookingPassengerID 21–35)
-- Adults are inserted before minors within each cabin so the
-- guardian check in TR_BookingPassenger_BI_ValidateRules succeeds.
-- FinalFare and FareRuleID are hardcoded (trigger also computes them).
-- AgeCategoryID: 2=Child  3=Teen  4=Adult  5=Senior
-- ----------------------------------------------------------------
INSERT INTO BookingPassenger
    (BookingID, BookingCabinID, PassengerID, AgeCategoryID, FareRuleID,
     InfantBedOption, IsChaperonedYouth, DailySupervisionFee, FinalFare)
VALUES
/* --- Booking 9: Interior V3 — 2 Adults (Adult Interior V3 = FareRuleID=35, 750.00) ---- */
(9,  10, 21, 4, 35, 'NotApplicable', FALSE, 0.00,  750.00),   -- BPID=21  Marco
(9,  10, 22, 4, 35, 'NotApplicable', FALSE, 0.00,  750.00),   -- BPID=22  Giulia

/* --- Booking 10: OceanView V3 — 1 Adult + 1 Senior ------------------------------------ */
/* Adult OceanView V3 = FareRuleID=39, 950.00 | Senior OceanView V3 = FareRuleID=40, 850.00 */
(10, 11, 23, 4, 39, 'NotApplicable', FALSE, 0.00,  950.00),   -- BPID=23  Thomas   Adult
(10, 11, 24, 5, 40, 'NotApplicable', FALSE, 0.00,  850.00),   -- BPID=24  Elizabeth Senior

/* --- Booking 11: Balcony V3 — 2 Adults (Adult Balcony V3 = FareRuleID=43, 1 300.00) --- */
(11, 12, 25, 4, 43, 'NotApplicable', FALSE, 0.00, 1300.00),   -- BPID=25  Chen Wei
(11, 12, 26, 4, 43, 'NotApplicable', FALSE, 0.00, 1300.00),   -- BPID=26  Li Mei

/* --- Booking 12: Interior V4 — 2 Adults (Adult Interior V4 = FareRuleID=51, 900.00) --- */
(12, 13, 27, 4, 51, 'NotApplicable', FALSE, 0.00,  900.00),   -- BPID=27  Jack
(12, 13, 28, 4, 51, 'NotApplicable', FALSE, 0.00,  900.00),   -- BPID=28  Emily

/* --- Booking 13: OceanView V4 — 1 Senior (Senior OceanView V4 = FareRuleID=56, 1 050.00) */
(13, 14, 29, 5, 56, 'NotApplicable', FALSE, 0.00, 1050.00),   -- BPID=29  Robert   Senior

/* --- Booking 14: Balcony V5 — 2 Adults (Adult Balcony V5 = FareRuleID=75, 2 700.00) --- */
(14, 15, 30, 4, 75, 'NotApplicable', FALSE, 0.00, 2700.00),   -- BPID=30  Amir
(14, 15, 31, 4, 75, 'NotApplicable', FALSE, 0.00, 2700.00),   -- BPID=31  Priya

/* --- Booking 15: Interior V5 — 1 Adult then 1 Child ----------------------------------- */
/* Adult inserted first so the child guardian check finds an adult already in the cabin.   */
/* Adult Interior V5 = FareRuleID=67, 1 800.00 | Child Interior V5 = FareRuleID=65, 1 000.00 */
(15, 16, 32, 4, 67, 'NotApplicable', FALSE, 0.00, 1800.00),   -- BPID=32  Tan Boon Hua  Adult
(15, 16, 33, 2, 65, 'NotApplicable', FALSE, 0.00, 1000.00),   -- BPID=33  Mei Xin Tan   Child

/* --- Booking 16: Suite V5 — 2 Adults (Adult Suite V5 = FareRuleID=79, 4 800.00) ------- */
(16, 17, 34, 4, 79, 'NotApplicable', FALSE, 0.00, 4800.00),   -- BPID=34  David
(16, 17, 35, 4, 79, 'NotApplicable', FALSE, 0.00, 4800.00);   -- BPID=35  Grace

-- ----------------------------------------------------------------
-- BOOKING BAGGAGE
-- IsOverLimit hardcoded by comparing WeightKG against voyage limit.
--   Voyage 3 limit = 23 kg | Voyage 4 limit = 25 kg | Voyage 5 limit = 28 kg
-- ----------------------------------------------------------------
INSERT INTO BookingBaggage (BookingPassengerID, WeightKG, IsOverLimit, ExcessFee)
VALUES
-- Booking 9 (V3, 23 kg limit)
(21, 20.00, FALSE, 0),   -- Marco:    20.0 kg ✓
(22, 18.50, FALSE, 0),   -- Giulia:   18.5 kg ✓
-- Booking 10 (V3, 23 kg limit)
(23, 22.50, FALSE, 0),   -- Thomas:   22.5 kg ✓
(24, 19.00, FALSE, 0),   -- Elizabeth:19.0 kg ✓
-- Booking 11 (V3, 23 kg limit)
(25, 24.50, TRUE,  0),   -- Chen Wei: 24.5 kg ✗ over 23 kg limit
(26, 17.00, FALSE, 0),   -- Li Mei:   17.0 kg ✓
-- Booking 12 (V4, 25 kg limit)
(27, 23.00, FALSE, 0),   -- Jack:     23.0 kg ✓
(28, 21.50, FALSE, 0),   -- Emily:    21.5 kg ✓
-- Booking 13 (V4, 25 kg limit)
(29, 27.00, TRUE,  0),   -- Robert:   27.0 kg ✗ over 25 kg limit
-- Booking 14 (V5, 28 kg limit)
(30, 26.00, FALSE, 0),   -- Amir:     26.0 kg ✓
(31, 22.00, FALSE, 0),   -- Priya:    22.0 kg ✓
-- Booking 15 (V5, 28 kg limit)
(32, 30.00, TRUE,  0),   -- Tan:      30.0 kg ✗ over 28 kg limit
(33,  8.00, FALSE, 0),   -- Mei Xin:   8.0 kg ✓
-- Booking 16 (V5, 28 kg limit)
(34, 25.00, FALSE, 0),   -- David:    25.0 kg ✓
(35, 23.50, FALSE, 0);   -- Grace:    23.5 kg ✓

-- ----------------------------------------------------------------
-- PAYMENTS  (PaymentID 9–16)
-- ----------------------------------------------------------------
INSERT INTO Payment (BookingID, PaymentDateTime, Amount, PaymentMethod, PaymentStatus, TransactionReference)
VALUES
(9,  '2026-01-15 09:30:00',  1500.00, 'Credit Card',   'Paid', 'TXN-20260115-009'),
(10, '2026-01-20 14:20:00',  1800.00, 'Bank Transfer', 'Paid', 'TXN-20260120-010'),
(11, '2026-02-01 11:15:00',  2600.00, 'Debit Card',    'Paid', 'TXN-20260201-011'),
(12, '2026-02-10 10:30:00',  1800.00, 'Credit Card',   'Paid', 'TXN-20260210-012'),
(13, '2026-02-15 15:20:00',  1050.00, 'Credit Card',   'Paid', 'TXN-20260215-013'),
(14, '2026-07-20 08:30:00',  5400.00, 'Bank Transfer', 'Paid', 'TXN-20260720-014'),
(15, '2026-07-25 13:15:00',  2800.00, 'Credit Card',   'Paid', 'TXN-20260725-015'),
(16, '2026-08-01 10:45:00',  9600.00, 'Debit Card',    'Paid', 'TXN-20260801-016');

SELECT 'Additional sample data loaded successfully.' AS Message;