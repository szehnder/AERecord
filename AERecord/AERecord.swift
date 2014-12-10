//
// AERecord.swift
//
// Copyright (c) 2014 Marko Tadic - http://markotadic.com
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

import Foundation
import CoreData

let kAERecordPrintLog = true

// MARK: - AERecord (AEStack.sharedInstance Shortcuts)
public class AERecord {
    
    // MARK: Properties
    
    public class var defaultContext: NSManagedObjectContext { return AEStack.sharedInstance.defaultContext } // context for current thread
    public class var mainContext: NSManagedObjectContext { return AEStack.sharedInstance.mainContext } // context for main thread
    public class var backgroundContext: NSManagedObjectContext { return AEStack.sharedInstance.backgroundContext } // context for background thread
    
    public class var persistentStoreCoordinator: NSPersistentStoreCoordinator? { return AEStack.sharedInstance.persistentStoreCoordinator }
    
    // MARK: Setup Stack
    
    public class func storeURLForName(name: String) -> NSURL {
        return AEStack.storeURLForName(name)
    }
    
    public class func loadCoreDataStack(managedObjectModel: NSManagedObjectModel = AEStack.defaultModel, storeType: String = NSSQLiteStoreType, configuration: String? = nil, storeURL: NSURL = AEStack.defaultURL, options: [NSObject : AnyObject]? = nil) -> NSError? {
        return AEStack.sharedInstance.loadCoreDataStack(managedObjectModel: managedObjectModel, storeType: storeType, configuration: configuration, storeURL: storeURL, options: options)
    }
    
    public class func destroyCoreDataStack(storeURL: NSURL = AEStack.defaultURL) {
        AEStack.sharedInstance.destroyCoreDataStack(storeURL: storeURL)
    }
    
    public class func truncateAllData(context: NSManagedObjectContext? = nil) {
        AEStack.sharedInstance.truncateAllData(context: context)
    }
    
    // MARK: Context Execute
    
    public class func executeFetchRequest(request: NSFetchRequest, context: NSManagedObjectContext? = nil) -> [NSManagedObject] {
        return AEStack.sharedInstance.executeFetchRequest(request, context: context)
    }
    
    // MARK: Context Save
    
    public class func saveContext(context: NSManagedObjectContext? = nil) {
        AEStack.sharedInstance.saveContext(context: context)
    }
    
    public class func saveContextAndWait(context: NSManagedObjectContext? = nil) {
        AEStack.sharedInstance.saveContextAndWait(context: context)
    }
    
}

// MARK: - CoreData Stack (AERecord heart:)
private class AEStack {
    
    // MARK: Shared Instance
    
    class var sharedInstance: AEStack  {
        struct Singleton {
            static let instance = AEStack()
        }
        return Singleton.instance
    }
    
    // MARK: Default settings
    
    class var bundleIdentifier: String {
        return NSBundle.mainBundle().bundleIdentifier!
    }
    class var defaultURL: NSURL {
        return storeURLForName(bundleIdentifier)
    }
    class var defaultModel: NSManagedObjectModel {
        return NSManagedObjectModel.mergedModelFromBundles(nil)!
    }
    
    // MARK: Properties
    
    var managedObjectModel: NSManagedObjectModel?
    var persistentStoreCoordinator: NSPersistentStoreCoordinator?
    var mainContext: NSManagedObjectContext!
    var backgroundContext: NSManagedObjectContext!
    var defaultContext: NSManagedObjectContext {
        if NSThread.isMainThread() {
            return mainContext
        } else {
            return backgroundContext
        }
    }
    
    // MARK: Setup Stack
    
    class func storeURLForName(name: String) -> NSURL {
        let applicationDocumentsDirectory = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).last as NSURL
        let storeName = "\(name).sqlite"
        return applicationDocumentsDirectory.URLByAppendingPathComponent(storeName)
    }
    
    func loadCoreDataStack(managedObjectModel: NSManagedObjectModel = defaultModel,
        storeType: String = NSSQLiteStoreType,
        configuration: String? = nil,
        storeURL: NSURL = defaultURL,
        options: [NSObject : AnyObject]? = nil) -> NSError?
    {
        self.managedObjectModel = managedObjectModel
        
        // setup main and background contexts
        mainContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        backgroundContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        
        // create the coordinator and store
        persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        if let coordinator = persistentStoreCoordinator {
            var error: NSError?
            if coordinator.addPersistentStoreWithType(storeType, configuration: configuration, URL: storeURL, options: options, error: &error) == nil {
                let dict = NSMutableDictionary()
                dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data"
                dict[NSLocalizedFailureReasonErrorKey] = "There was an error creating or loading the application's saved data."
                dict[NSUnderlyingErrorKey] = error
                error = NSError(domain: AEStack.bundleIdentifier, code: 1, userInfo: dict)
                if let err = error {
                    if kAERecordPrintLog {
                        println("Error occured in \(NSStringFromClass(self.dynamicType)) - function: \(__FUNCTION__) | line: \(__LINE__)\n\(err)")
                    }
                }
                return error
            } else {
                // everything went ok
                mainContext.persistentStoreCoordinator = coordinator
                backgroundContext.persistentStoreCoordinator = coordinator
                startReceivingContextNotifications()
                return nil
            }
        } else {
            return NSError(domain: AEStack.bundleIdentifier, code: 2, userInfo: [NSLocalizedDescriptionKey : "Could not create NSPersistentStoreCoordinator from given NSManagedObjectModel."])
        }
    }
    
    func destroyCoreDataStack(storeURL: NSURL = defaultURL) -> NSError? {
        // must load this core data stack first
        loadCoreDataStack(storeURL: storeURL) // because there is no persistentStoreCoordinator if destroyCoreDataStack is called before loadCoreDataStack
        // also if we're in other stack currently that persistentStoreCoordinator doesn't know about this storeURL
        stopReceivingContextNotifications() // stop receiving notifications for these contexts
        // reset contexts
        mainContext.reset()
        backgroundContext.reset()
        // finally, remove persistent store
        var error: NSError?
        if let coordinator = persistentStoreCoordinator {
            if let store = coordinator.persistentStoreForURL(storeURL) {
                if coordinator.removePersistentStore(store, error: &error) {
                    NSFileManager.defaultManager().removeItemAtURL(storeURL, error: &error)
                }
            }
        }
        // reset coordinator and model
        persistentStoreCoordinator = nil
        managedObjectModel = nil

        if let err = error {
            if kAERecordPrintLog {
                println("Error occured in \(NSStringFromClass(self.dynamicType)) - function: \(__FUNCTION__) | line: \(__LINE__)\n\(err)")
            }
        }
        return error ?? nil
    }
    
    func truncateAllData(context: NSManagedObjectContext? = nil) {
        let moc = context ?? defaultContext
        if let mom = managedObjectModel {
            for entity in mom.entities as [NSEntityDescription] {
                if let entityType = NSClassFromString(entity.managedObjectClassName) as? NSManagedObject.Type {
                    entityType.deleteAll(context: moc)
                }
            }
        }
    }
    
    deinit {
        stopReceivingContextNotifications()
        if kAERecordPrintLog {
            println("\(NSStringFromClass(self.dynamicType)) deinitialized - function: \(__FUNCTION__) | line: \(__LINE__)\n")
        }
    }
    
    // MARK: Context Execute
    
    func executeFetchRequest(request: NSFetchRequest, context: NSManagedObjectContext? = nil) -> [NSManagedObject] {
        var fetchedObjects = [NSManagedObject]()
        let moc = context ?? defaultContext
        moc.performBlockAndWait { () -> Void in
            var error: NSError?
            if let result = moc.executeFetchRequest(request, error: &error) {
                if let managedObjects = result as? [NSManagedObject] {
                    fetchedObjects = managedObjects
                }
            }
            if let err = error {
                if kAERecordPrintLog {
                    println("Error occured in \(NSStringFromClass(self.dynamicType)) - function: \(__FUNCTION__) | line: \(__LINE__)\n\(err)")
                }
            }
        }
        return fetchedObjects
    }
    
    // MARK: Context Save
    
    func saveContext(context: NSManagedObjectContext? = nil) {
        let moc = context ?? defaultContext
        moc.performBlock { () -> Void in
            var error: NSError?
            if moc.hasChanges && !moc.save(&error) {
                if let err = error {
                    if kAERecordPrintLog {
                        println("Error occured in \(NSStringFromClass(self.dynamicType)) - function: \(__FUNCTION__) | line: \(__LINE__)\n\(err)")
                    }
                }
            }
        }
    }
    
    func saveContextAndWait(context: NSManagedObjectContext? = nil) {
        let moc = context ?? defaultContext
        moc.performBlockAndWait { () -> Void in
            var error: NSError?
            if moc.hasChanges && !moc.save(&error) {
                if let err = error {
                    if kAERecordPrintLog {
                        println("Error occured in \(NSStringFromClass(self.dynamicType)) - function: \(__FUNCTION__) | line: \(__LINE__)\n\(err)")
                    }
                }
            }
        }
    }
    
    // MARK: Context Sync
    
    func startReceivingContextNotifications() {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "contextDidSave:", name: NSManagedObjectContextDidSaveNotification, object: mainContext)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "contextDidSave:", name: NSManagedObjectContextDidSaveNotification, object: backgroundContext)
    }
    
    func stopReceivingContextNotifications() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    @objc func contextDidSave(notification: NSNotification) {
        if let context = notification.object as? NSManagedObjectContext {
            let contextToRefresh = context == mainContext ? backgroundContext : mainContext
            contextToRefresh.performBlock({ () -> Void in
                contextToRefresh.mergeChangesFromContextDidSaveNotification(notification)
            })
        }
    }
    
}

// MARK: - NSManagedObject Extension
extension NSManagedObject {
    
    // MARK: General
    
    public class var entityName: String {
        var name = NSStringFromClass(self)
        name = name.componentsSeparatedByString(".").last
        return name
    }
    
    public class func createFetchRequest(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> NSFetchRequest {
        // create request
        let request = NSFetchRequest(entityName: entityName)
        // set request parameters
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return request
    }
    
    // MARK: Creating
    
    public class func create(context: NSManagedObjectContext = AERecord.defaultContext) -> Self {
        let entityDescription = NSEntityDescription.entityForName(entityName, inManagedObjectContext: context)
        let object = self(entity: entityDescription!, insertIntoManagedObjectContext: context)
        return object
    }
    
    public class func createWithAttributes(attributes: [NSObject : AnyObject], context: NSManagedObjectContext = AERecord.defaultContext) -> Self {
        let object = create(context: context)
        if attributes.count > 0 {
            object.setValuesForKeysWithDictionary(attributes)
        }
        return object
    }
    
    public class func firstOrCreateWithAttribute(attribute: String, value: AnyObject, context: NSManagedObjectContext = AERecord.defaultContext) -> NSManagedObject {
        let predicate = NSPredicate(format: "%K = %@", attribute, value as NSObject)
        let request = createFetchRequest(predicate: predicate)
        request.fetchLimit = 1
        let objects = AERecord.executeFetchRequest(request, context: context)
        return objects.first ?? createWithAttributes([attribute : value], context: context)
    }
    
    // MARK: Deleting
    
    public func delete(context: NSManagedObjectContext = AERecord.defaultContext) {
        context.deleteObject(self)
    }
    
    public class func deleteAll(context: NSManagedObjectContext = AERecord.defaultContext) {
        if let objects = self.all(context: context) {
            for object in objects {
                context.deleteObject(object)
            }
        }
    }
    
    public class func deleteAllWithPredicate(predicate: NSPredicate, context: NSManagedObjectContext = AERecord.defaultContext) {
        if let objects = self.allWithPredicate(predicate, context: context) {
            for object in objects {
                context.deleteObject(object)
            }
        }
    }
    
    public class func deleteAllWithAttribute(attribute: String, value: AnyObject, context: NSManagedObjectContext = AERecord.defaultContext) {
        if let objects = self.allWithAttribute(attribute, value: value, context: context) {
            for object in objects {
                context.deleteObject(object)
            }
        }
    }
    
    // MARK: Finding First
    
    public class func first(sortDescriptors: [NSSortDescriptor]? = nil, context: NSManagedObjectContext = AERecord.defaultContext) -> NSManagedObject? {
        let request = createFetchRequest(sortDescriptors: sortDescriptors)
        request.fetchLimit = 1
        let objects = AERecord.executeFetchRequest(request, context: context)
        return objects.first ?? nil
    }
    
    public class func firstWithPredicate(predicate: NSPredicate, sortDescriptors: [NSSortDescriptor]? = nil, context: NSManagedObjectContext = AERecord.defaultContext) -> NSManagedObject? {
        let request = createFetchRequest(predicate: predicate, sortDescriptors: sortDescriptors)
        request.fetchLimit = 1
        let objects = AERecord.executeFetchRequest(request, context: context)
        return objects.first ?? nil
    }
    
    public class func firstWithAttribute(attribute: String, value: AnyObject, sortDescriptors: [NSSortDescriptor]? = nil, context: NSManagedObjectContext = AERecord.defaultContext) -> NSManagedObject? {
        let predicate = NSPredicate(format: "%K = %@", attribute, value as NSObject)
        return firstWithPredicate(predicate!, sortDescriptors: sortDescriptors, context: context)
    }
    
    public class func firstOrderedByAttribute(name: String, ascending: Bool = true, context: NSManagedObjectContext = AERecord.defaultContext) -> NSManagedObject? {
        let sortDescriptors = [NSSortDescriptor(key: name, ascending: ascending)]
        return first(sortDescriptors: sortDescriptors, context: context)
    }
    
    // MARK: Finding All
    
    public class func all(sortDescriptors: [NSSortDescriptor]? = nil, context: NSManagedObjectContext = AERecord.defaultContext) -> [NSManagedObject]? {
        let request = createFetchRequest(sortDescriptors: sortDescriptors)
        let objects = AERecord.executeFetchRequest(request, context: context)
        return objects.count > 0 ? objects : nil
    }
    
    public class func allWithPredicate(predicate: NSPredicate, sortDescriptors: [NSSortDescriptor]? = nil, context: NSManagedObjectContext = AERecord.defaultContext) -> [NSManagedObject]? {
        let request = createFetchRequest(predicate: predicate, sortDescriptors: sortDescriptors)
        let objects = AERecord.executeFetchRequest(request, context: context)
        return objects.count > 0 ? objects : nil
    }
    
    public class func allWithAttribute(attribute: String, value: AnyObject, sortDescriptors: [NSSortDescriptor]? = nil, context: NSManagedObjectContext = AERecord.defaultContext) -> [NSManagedObject]? {
        let predicate = NSPredicate(format: "%K = %@", attribute, value as NSObject)
        return allWithPredicate(predicate!, sortDescriptors: sortDescriptors, context: context)
    }
    
    // MARK: Auto Increment
    
    public class func autoIncrementedIntegerAttribute(attribute: String, context: NSManagedObjectContext = AERecord.defaultContext) -> Int {
        let sortDescriptor = NSSortDescriptor(key: attribute, ascending: false)
        if let object = self.first(sortDescriptors: [sortDescriptor], context: context) {
            if let max = object.valueForKey(attribute) as? Int {
                return max + 1
            } else {
                return 0
            }
        } else {
            return 0
        }
    }
    
    // MARK: Batch Updating
    
    public class func batchUpdate(predicate: NSPredicate? = nil, properties: [NSObject : AnyObject]? = nil, resultType: NSBatchUpdateRequestResultType = .StatusOnlyResultType, context: NSManagedObjectContext = AERecord.defaultContext) -> NSBatchUpdateResult? {
        // create request
        let request = NSBatchUpdateRequest(entityName: entityName)
        // set request parameters
        request.predicate = predicate
        request.propertiesToUpdate = properties
        request.resultType = resultType
        // execute request
        var batchResult: NSBatchUpdateResult? = nil
        context.performBlockAndWait { () -> Void in
            var error: NSError?
            if let result = context.executeRequest(request, error: &error) as? NSBatchUpdateResult {
                batchResult = result
            }
            if let err = error {
                if kAERecordPrintLog {
                    println("Error occured in \(NSStringFromClass(self.dynamicType)) - function: \(__FUNCTION__) | line: \(__LINE__)\n\(err)")
                }
            }
        }
        return batchResult
    }
    
    public class func objectsCountForBatchUpdate(predicate: NSPredicate? = nil, properties: [NSObject : AnyObject]? = nil, context: NSManagedObjectContext = AERecord.defaultContext) -> Int {
        if let result = batchUpdate(predicate: predicate, properties: properties, resultType: .UpdatedObjectsCountResultType, context: context) {
            if let count = result.result as? Int {
                return count
            } else {
                return 0
            }
        } else {
            return 0
        }
    }
    
    public class func batchUpdateAndRefreshObjects(predicate: NSPredicate? = nil, properties: [NSObject : AnyObject]? = nil, context: NSManagedObjectContext = AERecord.defaultContext) {
        if let result = batchUpdate(predicate: predicate, properties: properties, resultType: .UpdatedObjectIDsResultType, context: context) {
            if let objectIDS = result.result as? [NSManagedObjectID] {
                refreshObjects(objectIDS, mergeChanges: true, context: context)
            }
        }
    }
    
    public class func refreshObjects(objectIDS: [NSManagedObjectID], mergeChanges: Bool, context: NSManagedObjectContext = AERecord.defaultContext) {
        for objectID in objectIDS {
            var error: NSError?
            context.performBlockAndWait({ () -> Void in
                if let object = context.existingObjectWithID(objectID, error: &error) {
                    // turn managed objects into faults
                    if !object.fault {
                        context.refreshObject(object, mergeChanges: mergeChanges)
                    }
                }
                if let err = error {
                    if kAERecordPrintLog {
                        println("Error occured in \(NSStringFromClass(self.dynamicType)) - function: \(__FUNCTION__) | line: \(__LINE__)\n\(err)")
                    }
                }
            })
        }
    }
    
}



