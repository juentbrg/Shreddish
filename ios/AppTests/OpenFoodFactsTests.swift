import Foundation
import Testing
@testable import Shreddish

/// Lecture d'un produit Open Food Facts (spec 017).
struct OpenFoodFactsTests {
    @Test func parsesNutrimentsPer100g() throws {
        let json = #"""
        {"status":1,"product":{"product_name_fr":"Skyr nature","brands":"Siggi's,Arla",
         "serving_quantity":"150","nutriments":{"energy-kcal_100g":63,"proteins_100g":11,
         "carbohydrates_100g":4,"fat_100g":0.2}}}
        """#
        let food = try OpenFoodFactsClient.parse(Data(json.utf8), barcode: "123")
        #expect(food.name == "Skyr nature · Siggi's")
        #expect(food.per100g.kcal == 63)
        #expect(food.per100g.proteinG == 11)
        #expect(food.servingG == 150)
    }

    @Test func unknownProductIsNotFound() {
        #expect(throws: OpenFoodFactsClient.Failure.notFound) {
            try OpenFoodFactsClient.parse(Data(#"{"status":0}"#.utf8), barcode: "1")
        }
    }

    @Test func missingValuesAreIncomplete() {
        let json = #"{"status":1,"product":{"product_name":"X","nutriments":{"proteins_100g":3}}}"#
        #expect(throws: OpenFoodFactsClient.Failure.incomplete) {
            try OpenFoodFactsClient.parse(Data(json.utf8), barcode: "1")
        }
    }
}
