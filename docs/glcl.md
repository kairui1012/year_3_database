Case Study: GLOBAL LUXURY CRUISE LINES (GLCL)
Global Luxury Cruise Lines (GLCL) is a premier company managing global reservations for multiple international cruise operators. Its head office is located in Kuala Lumpur, Malaysia. Passengers can book cabins in one of four categories: Interior, Ocean View, Balcony, and Suite. Sailings are offered as One-way (repositioning cruises), Round-trip, and Multi-destination (island hopping) itineraries.
Multiple dining options are available depending on the ship, ranging from standard set-time dining to flexible anytime dining and specialty restaurants. The length of the sailing determines whether passengers receive standard boarding meals or an all-inclusive multi-day meal package. Special services, such as on-board child-care and exclusive teen clubs, are provided based on age. Fares are calculated based on the following passenger age categories:
•	Infant (Ages: under 2)
•	Child (Ages: 2-12)
•	Teen (Ages: 13-17)
•	Adult (Ages: 18-59)
•	Senior (Ages: 60 or over)
The fare for an infant depends on whether they require a standalone crib or are sharing existing bedding. If sharing bedding, the cruise charges a nominal fee of 15% of the adult fare; if a crib/cot is required, they are charged 50% of the child fare. Cabins have a strict maximum occupancy of 5 passengers per booking. Safety regulations dictate that a teen aged up to 17 cannot travel in a cabin alone unless an adult guardian (18 or older) is booked in an adjacent or connecting cabin. Alternatively, some cruise operators offer a "Chaperoned Youth" program for teens aged 15-17 traveling for educational trips, subject to a mandatory daily supervision fee. Wheelchair-accessible cabins and mobility assistance services are provided by all operators upon request.
General constraints and maritime rules apply to all reservations, including strict baggage weight limits. Cancellations and itinerary changes can be made with additional fees, subject to the ticket's fare rules. If a sailing has not yet commenced, a ticket can be transferred to a new date, but the new voyage must begin within one year of the original booking date. If a traveler cancels or attempts to change their itinerary less than 48 hours before the ship's scheduled departure from the home port, they will forfeit the entire ticket value.
Project Scope: You are required to design a database covering the following areas:
•	Cruise Reservations
•	Cruise Cancellations & Rescheduling



 
Requirements:

1	DESIGN

(a)	Develop an ERD to support GLCL’s activities. The ERD must show entities and relationships and should be followed by a logical design. Identify primary and foreign keys and show cardinality and optionality. Data must be in 3NF or higher unless it has been denormalized for performance reasons, in which case a detailed explanation must be given. Your model should fully support the business requirements described above.
                                        (30 marks)

(b)	Document and provide a written description and justification of your optimization strategy. Each group member is required to produce one optimization strategy. 				
(10 marks)


(c)	Document all the constraints included in your system and justify and explain the constraints used and the ways in which they support the business rules. Provide a functional description of all the triggers. Each group member is required to design one constraint and trigger. 			      
   (10 marks)

2	IMPLEMENTATION

(a)	Implement your design and the optimization strategy.  You will be expected to demonstrate tables, referential integrity, appropriate test data, appropriate constraints and appropriate optimization techniques.  You will be expected to justify any mapping or denormalization issues. 
                                    (10 marks)

(b) 	Implement the triggers and constraints for which you developed functional descriptions.  You must be able to explain and justify the constraints and triggers during the presentation. Triggers which function but which the group cannot explain will receive zero marks.  Some marks may be awarded for non-functioning constraints and triggers where the group can identify the issues.
(10 marks)

(c)	Each group member is required to create and use T-SQL feature (choose from: stored procedure; or function) to support a business requirement or enhance usability. One good quality example is sufficient, but you must be able to explain why and how you would use this feature and what benefits it offers compared to other possible implementation approaches. Features which function but which the group cannot explain will receive zero marks.  Some marks may be rewarded for features which do not function fully but where the group can explain the issues.	
                                         (10 marks)



(d) 	Create the following queries – this section is worth 20 marks in total. Groups must be able to explain the queries and justify the approach taken. Marks will be reduced where groups cannot explain how they have arrived at their solutions.

Member 1

i.	Create a query which shows round-trip sailings only for given dates, departure port, and arrival port.	
        (2 marks)
                        
ii.	Create a query which shows the ship code, cabin category code, and expected revenue for each cabin category, along with the total revenue of each ship for a given cruise operator on a single voyage
         (2 marks)

iii.	Create a query which shows all passenger IDs with their corresponding textual descriptions of reservation status (e.g., Confirmed, Cancelled, Waitlisted) for a specific cruise operator.
(2 marks)

iv.	Create a query which shows the name of the cruise operator that has been most frequently booked by passengers for a specified departure port in a given range of dates.  				 (2 marks)

             v.	Create a query which provides, for each age category of passengers, the following information: The total number of infants, children, teens, adults, & seniors traveling on a specified voyage operated by a given cruise line. The result should contain both a detailed breakup & summary for the above-mentioned categories, along with an overall grand total. (Hint: use ROLLUP or CUBE).												 (7 marks)

vi.	Create a query which shows the cruise operator offering the maximum number of multi-destination itineraries, along with the names of the departure and final arrival ports. 				(2 marks)


vii.	Develop one additional query of your own which provides information that would be useful for the business. Marks will be awarded depending on the technical skills shown and the relevance of the query.
                                 (3 marks) 



Member 2

viii.	Create a query which displays sailing details, such as the ship code, regular fare, and discounted fare for the "Suite" category. A 15% early-bird discount is currently being offered. Label the columns as Ship Code, Regular Suite Fare, and Discounted Suite Fare.		
                                    (2 marks)
                        
ix.	Create a query which displays the sorted details of sailings to a given destination port code, with the shortest duration voyage displayed first.
         (2 marks)

x.	Create a query which displays the types of specialty (e.g., gluten-free, vegan) dining options offered on specific ships. 		(2 marks)

xi.	Create a query which shows the names of countries where GLCL ships are scheduled to dock. Ensure that duplicate country names are eliminated from the final list.				  	(2 marks)

             xii.	Create a query which provides, for each cruise operator, the following information: The total number of voyages scheduled on a given departure date. The result should contain both a detailed breakup & summary for voyages for each cruise operator along with an overall summary. (Hint: use ROLLUP or CUBE).												(7 marks)

xiii.	Create a query which shows the names of the onshore excursion options available for a given ship's itinerary.			 									            (2 marks)

xiv.	Develop one additional query of your own which provides information that would be useful for the business.													 (3 marks) 

Member 3

xv.	Create a query which shows the minimum, maximum, and average voyage duration (in days) for sailings to a given destination port code. Display column headings as Minimum Duration, Maximum Duration, and Average Duration.					(2 marks)
                    
xvi.	Create a query which shows the departure date, number of booked passengers in the party, and cabin category name for a specifically given passenger ID. 					  		 (2 marks)

xvii.	Find the excursions with no sales.				 (2 marks)

xviii.	Create a query which shows the details of passengers booked through a specified cruise operator on a given date for "multi-destination" island-hopping itineraries.				  		 (2 marks)

            xix.	Create a query which provides, for each cruise operator, the following information: The total number of passengers requesting wheelchair assistance traveling on a given date. The result should contain both a detailed breakup & summary for these passengers for each cruise operator along with an overall summary. (Hint: use ROLLUP or CUBE								(7 marks)

xx.	Create a query which shows the details of passengers who have availed of the "Chaperoned Youth" extra service for a given sailing on a specified date. 						(2 marks)

xxi. 	Develop one additional query of your own which provides information that would be useful for the business.				 									(3 marks)

