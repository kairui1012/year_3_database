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

