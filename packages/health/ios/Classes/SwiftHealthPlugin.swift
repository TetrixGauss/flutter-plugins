import Flutter
import UIKit
import HealthKit

public class SwiftHealthPlugin: NSObject, FlutterPlugin {

    let healthStore = HKHealthStore()
    var healthDataTypes = [HKSampleType]()
    var heartRateEventTypes = Set<HKSampleType>()
    var seriesData = Set<HKSampleType>()
    var allDataTypes = Set<HKSampleType>()
    var dataTypesDict: [String: HKSampleType] = [:]
    var unitDict: [String: HKUnit] = [:]

    // Health Data Type Keys
    let ACTIVE_ENERGY_BURNED = "ACTIVE_ENERGY_BURNED"
    let BASAL_ENERGY_BURNED = "BASAL_ENERGY_BURNED"
    let BLOOD_GLUCOSE = "BLOOD_GLUCOSE"
    let BLOOD_OXYGEN = "BLOOD_OXYGEN"
    let BLOOD_PRESSURE_DIASTOLIC = "BLOOD_PRESSURE_DIASTOLIC"
    let BLOOD_PRESSURE_SYSTOLIC = "BLOOD_PRESSURE_SYSTOLIC"
    let BODY_FAT_PERCENTAGE = "BODY_FAT_PERCENTAGE"
    let BODY_MASS_INDEX = "BODY_MASS_INDEX"
    let BODY_TEMPERATURE = "BODY_TEMPERATURE"
    let DIETARY_CARBS_CONSUMED = "DIETARY_CARBS_CONSUMED"
    let DIETARY_ENERGY_CONSUMED = "DIETARY_ENERGY_CONSUMED"
    let DIETARY_FATS_CONSUMED = "DIETARY_FATS_CONSUMED"
    let DIETARY_PROTEIN_CONSUMED = "DIETARY_PROTEIN_CONSUMED"
    let ELECTRODERMAL_ACTIVITY = "ELECTRODERMAL_ACTIVITY"
    let FORCED_EXPIRATORY_VOLUME = "FORCED_EXPIRATORY_VOLUME"
    let HEART_RATE = "HEART_RATE"
    let HEART_RATE_VARIABILITY_SDNN = "HEART_RATE_VARIABILITY_SDNN"
    let HEART_BEAT_SERIES = "HEART_BEAT_SERIES"
    let HEIGHT = "HEIGHT"
    let HIGH_HEART_RATE_EVENT = "HIGH_HEART_RATE_EVENT"
    let IRREGULAR_HEART_RATE_EVENT = "IRREGULAR_HEART_RATE_EVENT"
    let LOW_HEART_RATE_EVENT = "LOW_HEART_RATE_EVENT"
    let RESTING_HEART_RATE = "RESTING_HEART_RATE"
    let STEPS = "STEPS"
    let WAIST_CIRCUMFERENCE = "WAIST_CIRCUMFERENCE"
    let WALKING_HEART_RATE = "WALKING_HEART_RATE"
    let WEIGHT = "WEIGHT"
    let DISTANCE_WALKING_RUNNING = "DISTANCE_WALKING_RUNNING"
    let FLIGHTS_CLIMBED = "FLIGHTS_CLIMBED"
    let WATER = "WATER"
    let MINDFULNESS = "MINDFULNESS"
    let SLEEP_IN_BED = "SLEEP_IN_BED"
    let SLEEP_ASLEEP = "SLEEP_ASLEEP"
    let SLEEP_AWAKE = "SLEEP_AWAKE"
    let EXERCISE_TIME = "EXERCISE_TIME"
    let WORKOUT = "WORKOUT"


    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_health", binaryMessenger: registrar.messenger())
        let instance = SwiftHealthPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Set up all data types
        initializeTypes()

        /// Handle checkIfHealthDataAvailable
        if (call.method.elementsEqual("checkIfHealthDataAvailable")){
            checkIfHealthDataAvailable(call: call, result: result)
        }
        /// Handle requestAuthorization
        else if (call.method.elementsEqual("requestAuthorization")){
            requestAuthorization(call: call, result: result)
        }

        /// Handle getData
        else if (call.method.elementsEqual("getData")){
            getData(call: call, result: result)
        }

        /// Handle writeData
        else if (call.method.elementsEqual("writeData")){
            writeData(call: call, result: result)
        }
    }

    func checkIfHealthDataAvailable(call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(HKHealthStore.isHealthDataAvailable())
    }

    func requestAuthorization(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? NSDictionary
        let types = (arguments?["types"] as? Array) ?? []

        var typesToRequest = Set<HKSampleType>()

        for key in types {
            let keyString = "\(key)"
            typesToRequest.insert(dataTypeLookUp(key: keyString))
        }


        if #available(iOS 13.0, *) {
            typesToRequest.insert(HKSeriesType.heartbeat())
        }

        if #available(iOS 11.0, *) {
        // from health 3.3.1
//         healthStore.requestAuthorization(toShare: typesToRequest, read: typesToRequest) { (success, error) in
            healthStore.requestAuthorization(toShare: nil, read: typesToRequest) { (success, error) in
                result(success)
            }
        }
        else {
            result(false)// Handle the error here.
        }
    }

    func writeData(call: FlutterMethodCall, result: @escaping FlutterResult){
        guard let arguments = call.arguments as? NSDictionary,
            let value = (arguments["value"] as? Double),
            let type = (arguments["dataTypeKey"] as? String),
            let startDate = (arguments["startTime"] as? NSNumber),
            let endDate = (arguments["endTime"] as? NSNumber)
            else {
                print("writeData: Invalid arguments")
                return
            }

        let dateFrom = Date(timeIntervalSince1970: startDate.doubleValue / 1000)
        let dateTo = Date(timeIntervalSince1970: endDate.doubleValue / 1000)

        print("Successfully called writeData with value of \(value) and type of \(type)")

        let quantity = HKQuantity(unit: unitLookUp(key: type), doubleValue: value)

        let sample = HKQuantitySample(type: dataTypeLookUp(key: type) as! HKQuantityType, quantity: quantity, start: dateFrom, end: dateTo)

        HKHealthStore().save(sample, withCompletion: { (success, error) in
            if let err = error {
                print("Error Saving \(type) Sample: \(err.localizedDescription)")
            }
            DispatchQueue.main.async {
                result(success)
            }
        })
    }



    var count = 0

    @available(iOS 13.0, *)
    func fetchHeartbeats(sample : HKHeartbeatSeriesSample, group: DispatchGroup) -> [String:Any] {
        count+=1
        group.enter()

        let g = DispatchGroup()

        var beatToBeatData = [NSDictionary]()
        g.enter()
        let query = HKHeartbeatSeriesQuery(heartbeatSeries: sample) {
            (query, timeSinceSeriesStart, precededByGap, done, error) in

            guard error == nil else {
                print("Failed querying the raw heartbeat data: \(String(describing: error))")
                return
            }
            beatToBeatData.append([
                "timeSinceSeriesStart": timeSinceSeriesStart,
                "precededByGap": precededByGap
            ])


            if done {
                g.leave()
            }
        }

        HKHealthStore().execute(query)

        g.wait()

        let res: [String:Any] = [
                                  "uuid": "\(sample.uuid)",
                                  "value": sample.count,
                                  "date_from": Int(sample.startDate.timeIntervalSince1970 * 1000),
                                  "date_to": Int(sample.endDate.timeIntervalSince1970 * 1000),
                                  "source_id": sample.sourceRevision.source.bundleIdentifier,
                                  "source_name": sample.sourceRevision.source.name,
                                  "metadata": ["samples": beatToBeatData]
                              ]

        group.leave()
        return res
    }



    func getData(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? NSDictionary
        let dataTypeKey = (arguments?["dataTypeKey"] as? String) ?? "DEFAULT"
        let startDate = (arguments?["startDate"] as? NSNumber) ?? 0
        let endDate = (arguments?["endDate"] as? NSNumber) ?? 0
        let limit = (arguments?["limit"] as? Int) ?? HKObjectQueryNoLimit

        // Convert dates from milliseconds to Date()
        let dateFrom = Date(timeIntervalSince1970: startDate.doubleValue / 1000)
        let dateTo = Date(timeIntervalSince1970: endDate.doubleValue / 1000)

        let dataType = dataTypeLookUp(key: dataTypeKey)
        let predicate = HKQuery.predicateForSamples(withStart: dateFrom, end: dateTo, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        if #available(iOS 13, *), dataTypeKey == HEART_BEAT_SERIES {

            _ = HKQuery.predicateForSamples(withStart: dateFrom, end: dateTo, options: [])

            print("withStart: \(dateFrom) end: \(dateTo)")


            let dispatchQueue = DispatchQueue(label: "taskQueue") // serial queue
            let semaphore = DispatchSemaphore(value: 1)

            let group = DispatchGroup()

            var theSamples : [HKHeartbeatSeriesSample] = []

            group.enter()
            let heartBeatSeriesSample = HKSampleQuery(sampleType: HKSeriesType.heartbeat(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [self]
                (query, results, error) in
                guard let samples = results, ((samples.first as? HKHeartbeatSeriesSample) != nil) else {
                    print("Failed: no samples collected")
                    group.leave()
                    return
                }
                print("found \(samples.count) samples")

                // assign samples to theSamples
                samples.map { opt in
                    if let s = opt as? HKHeartbeatSeriesSample{
                        theSamples.append(s)
                    }
                }

                print("the samples: \(theSamples)")

                group.leave()

                return
            }
            HKHealthStore().execute(heartBeatSeriesSample)

            group.wait()

            print("fetching raw data of samples")

            var theResults: [[String:Any]] = []

            for optionalSample in theSamples {
                let sample = optionalSample as! HKHeartbeatSeriesSample
                let dic : [String:Any] = fetchHeartbeats(sample: sample, group: group)

                theResults.append(dic)
            }

            group.wait()
            result(theResults)
        }



        let query = HKSampleQuery(sampleType: dataType, predicate: predicate, limit: limit, sortDescriptors: [sortDescriptor]) {
            x, samplesOrNil, error in

            switch samplesOrNil {
            case let (samples as [HKQuantitySample]) as Any:

                DispatchQueue.main.async {
                    result(samples.map { sample -> NSDictionary in
                        let unit = self.unitLookUp(key: dataTypeKey)

                        return [
                            "uuid": "\(sample.uuid)",
                            "value": sample.quantity.doubleValue(for: unit),
                            "date_from": Int(sample.startDate.timeIntervalSince1970 * 1000),
                            "date_to": Int(sample.endDate.timeIntervalSince1970 * 1000),
                            "source_id": sample.sourceRevision.source.bundleIdentifier,
                            "source_name": sample.sourceRevision.source.name,
                            "metadata": sample.metadata
                        ]
                    })
                }

            case var (samplesCategory as [HKCategorySample]) as Any:
                if (dataTypeKey == self.SLEEP_IN_BED) {
                    samplesCategory = samplesCategory.filter { $0.value == 0 }
                }
                if (dataTypeKey == self.SLEEP_AWAKE) {
                    samplesCategory = samplesCategory.filter { $0.value == 2 }
                }
                if (dataTypeKey == self.SLEEP_ASLEEP) {
                    samplesCategory = samplesCategory.filter { $0.value == 1 }
                }

                DispatchQueue.main.async {
                    result(samplesCategory.map { sample -> NSDictionary in
                        return [
                            "uuid": "\(sample.uuid)",
                            "value": sample.value,
                            "date_from": Int(sample.startDate.timeIntervalSince1970 * 1000),
                            "date_to": Int(sample.endDate.timeIntervalSince1970 * 1000),
                            "source_id": sample.sourceRevision.source.bundleIdentifier,
                            "source_name": sample.sourceRevision.source.name
                        ]
                    })
                }

            case let (samplesWorkout as [HKWorkout]) as Any:
                DispatchQueue.main.async {
                    result(samplesWorkout.map { sample -> NSDictionary in
                        return [
                            "uuid": "\(sample.uuid)",
                            "value": Int(sample.duration),
                            "date_from": Int(sample.startDate.timeIntervalSince1970 * 1000),
                            "date_to": Int(sample.endDate.timeIntervalSince1970 * 1000),
                            "source_id": sample.sourceRevision.source.bundleIdentifier,
                            "source_name": sample.sourceRevision.source.name
                        ]
                    })
                }

            default:
                return
            }
        }

        HKHealthStore().execute(query)
    }

    func unitLookUp(key: String) -> HKUnit {
        guard let unit = unitDict[key] else {
            return HKUnit.count()
        }
        return unit
    }

    func dataTypeLookUp(key: String) -> HKSampleType {
        guard let dataType_ = dataTypesDict[key] else {
            return HKSampleType.quantityType(forIdentifier: .bodyMass)!
        }
        return dataType_
    }

    func initializeTypes() {
        unitDict[ACTIVE_ENERGY_BURNED] = HKUnit.kilocalorie()
        unitDict[BASAL_ENERGY_BURNED] = HKUnit.kilocalorie()
        unitDict[BLOOD_GLUCOSE] = HKUnit.init(from: "mg/dl")
        unitDict[BLOOD_OXYGEN] = HKUnit.percent()
        unitDict[BLOOD_PRESSURE_DIASTOLIC] = HKUnit.millimeterOfMercury()
        unitDict[BLOOD_PRESSURE_SYSTOLIC] = HKUnit.millimeterOfMercury()
        unitDict[BODY_FAT_PERCENTAGE] = HKUnit.percent()
        unitDict[BODY_MASS_INDEX] = HKUnit.init(from: "")
        unitDict[BODY_TEMPERATURE] = HKUnit.degreeCelsius()
        unitDict[DIETARY_CARBS_CONSUMED] = HKUnit.gram()
        unitDict[DIETARY_ENERGY_CONSUMED] = HKUnit.kilocalorie()
        unitDict[DIETARY_FATS_CONSUMED] = HKUnit.gram()
        unitDict[DIETARY_PROTEIN_CONSUMED] = HKUnit.gram()
        unitDict[ELECTRODERMAL_ACTIVITY] = HKUnit.siemen()
        unitDict[FORCED_EXPIRATORY_VOLUME] = HKUnit.liter()
        unitDict[HEART_RATE] = HKUnit.init(from: "count/min")
        unitDict[HEART_RATE_VARIABILITY_SDNN] = HKUnit.secondUnit(with: .milli)
        unitDict[HEART_BEAT_SERIES] = HKUnit.count()
        unitDict[HEIGHT] = HKUnit.meter()
        unitDict[RESTING_HEART_RATE] = HKUnit.init(from: "count/min")
        unitDict[STEPS] = HKUnit.count()
        unitDict[WAIST_CIRCUMFERENCE] = HKUnit.meter()
        unitDict[WALKING_HEART_RATE] = HKUnit.init(from: "count/min")
        unitDict[WEIGHT] = HKUnit.gramUnit(with: .kilo)
        unitDict[DISTANCE_WALKING_RUNNING] = HKUnit.meter()
        unitDict[FLIGHTS_CLIMBED] = HKUnit.count()
        unitDict[WATER] = HKUnit.liter()
        unitDict[MINDFULNESS] = HKUnit.init(from: "")
        unitDict[SLEEP_IN_BED] = HKUnit.init(from: "")
        unitDict[SLEEP_ASLEEP] = HKUnit.init(from: "")
        unitDict[SLEEP_AWAKE] = HKUnit.init(from: "")
        unitDict[EXERCISE_TIME] =  HKUnit.minute()
        unitDict[WORKOUT] = HKUnit.init(from: "")

        // Set up iOS 11 specific types (ordinary health data types)
        if #available(iOS 11.0, *) {
            dataTypesDict[ACTIVE_ENERGY_BURNED] = HKSampleType.quantityType(forIdentifier: .activeEnergyBurned)!
            dataTypesDict[BASAL_ENERGY_BURNED] = HKSampleType.quantityType(forIdentifier: .basalEnergyBurned)!
            dataTypesDict[BLOOD_GLUCOSE] = HKSampleType.quantityType(forIdentifier: .bloodGlucose)!
            dataTypesDict[BLOOD_OXYGEN] = HKSampleType.quantityType(forIdentifier: .oxygenSaturation)!
            dataTypesDict[BLOOD_PRESSURE_DIASTOLIC] = HKSampleType.quantityType(forIdentifier: .bloodPressureDiastolic)!
            dataTypesDict[BLOOD_PRESSURE_SYSTOLIC] = HKSampleType.quantityType(forIdentifier: .bloodPressureSystolic)!
            dataTypesDict[BODY_FAT_PERCENTAGE] = HKSampleType.quantityType(forIdentifier: .bodyFatPercentage)!
            dataTypesDict[BODY_MASS_INDEX] = HKSampleType.quantityType(forIdentifier: .bodyMassIndex)!
            dataTypesDict[BODY_TEMPERATURE] = HKSampleType.quantityType(forIdentifier: .bodyTemperature)!
            dataTypesDict[DIETARY_CARBS_CONSUMED] = HKSampleType.quantityType(forIdentifier: .dietaryCarbohydrates)!
            dataTypesDict[DIETARY_ENERGY_CONSUMED] = HKSampleType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
            dataTypesDict[DIETARY_FATS_CONSUMED] = HKSampleType.quantityType(forIdentifier: .dietaryFatTotal)!
            dataTypesDict[DIETARY_PROTEIN_CONSUMED] = HKSampleType.quantityType(forIdentifier: .dietaryProtein)!
            dataTypesDict[ELECTRODERMAL_ACTIVITY] = HKSampleType.quantityType(forIdentifier: .electrodermalActivity)!
            dataTypesDict[FORCED_EXPIRATORY_VOLUME] = HKSampleType.quantityType(forIdentifier: .forcedExpiratoryVolume1)!
            dataTypesDict[HEART_RATE] = HKSampleType.quantityType(forIdentifier: .heartRate)!
            dataTypesDict[HEART_RATE_VARIABILITY_SDNN] = HKSampleType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
            dataTypesDict[HEIGHT] = HKSampleType.quantityType(forIdentifier: .height)!
            dataTypesDict[RESTING_HEART_RATE] = HKSampleType.quantityType(forIdentifier: .restingHeartRate)!
            dataTypesDict[STEPS] = HKSampleType.quantityType(forIdentifier: .stepCount)!
            dataTypesDict[WAIST_CIRCUMFERENCE] = HKSampleType.quantityType(forIdentifier: .waistCircumference)!
            dataTypesDict[WALKING_HEART_RATE] = HKSampleType.quantityType(forIdentifier: .walkingHeartRateAverage)!
            dataTypesDict[WEIGHT] = HKSampleType.quantityType(forIdentifier: .bodyMass)!
            dataTypesDict[DISTANCE_WALKING_RUNNING] = HKSampleType.quantityType(forIdentifier: .distanceWalkingRunning)!
            dataTypesDict[FLIGHTS_CLIMBED] = HKSampleType.quantityType(forIdentifier: .flightsClimbed)!
            dataTypesDict[WATER] = HKSampleType.quantityType(forIdentifier: .dietaryWater)!
            dataTypesDict[MINDFULNESS] = HKSampleType.categoryType(forIdentifier: .mindfulSession)!
            dataTypesDict[SLEEP_IN_BED] = HKSampleType.categoryType(forIdentifier: .sleepAnalysis)!
            dataTypesDict[SLEEP_ASLEEP] = HKSampleType.categoryType(forIdentifier: .sleepAnalysis)!
            dataTypesDict[SLEEP_AWAKE] = HKSampleType.categoryType(forIdentifier: .sleepAnalysis)!
            dataTypesDict[EXERCISE_TIME] = HKSampleType.quantityType(forIdentifier: .appleExerciseTime)!
            dataTypesDict[WORKOUT] = HKSampleType.workoutType()

            healthDataTypes = Array(dataTypesDict.values)
        }
        // Set up heart rate data types specific to the apple watch, requires iOS 12
        if #available(iOS 12.2, *){
            dataTypesDict[HIGH_HEART_RATE_EVENT] = HKSampleType.categoryType(forIdentifier: .highHeartRateEvent)!
            dataTypesDict[LOW_HEART_RATE_EVENT] = HKSampleType.categoryType(forIdentifier: .lowHeartRateEvent)!
            dataTypesDict[IRREGULAR_HEART_RATE_EVENT] = HKSampleType.categoryType(forIdentifier: .irregularHeartRhythmEvent)!

            heartRateEventTypes =  Set([
                HKSampleType.categoryType(forIdentifier: .highHeartRateEvent)!,
                HKSampleType.categoryType(forIdentifier: .lowHeartRateEvent)!,
                HKSampleType.categoryType(forIdentifier: .irregularHeartRhythmEvent)!,
                ])
        }

        if #available(iOS 13.0 , *){
            dataTypesDict[HEART_BEAT_SERIES] = HKSampleType.seriesType(forIdentifier: HKDataTypeIdentifierHeartbeatSeries)!

            seriesData = Set([
                HKSampleType.seriesType(forIdentifier: HKDataTypeIdentifierHeartbeatSeries)!,
            ])
        }

        // Concatenate heart events and health data types (both may be empty)
        allDataTypes = Set(heartRateEventTypes + healthDataTypes + seriesData)
    }
}




