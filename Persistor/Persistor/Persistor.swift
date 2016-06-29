//
//  Persistor.swift
//  Persistor
//
//  Created by Keegan Rush on 2016/06/29.
//  Copyright © 2016 Rush42. All rights reserved.
//

import CoreData

public class Persistor: NSObject
{
    // MARK: - Properties
    
    let managedObjectContext: NSManagedObjectContext
    let backgroundManagedObjectContext: NSManagedObjectContext
    let managedObjectModel: NSManagedObjectModel
    let persistentStoreCoordinator: NSPersistentStoreCoordinator
    
    private var contextForCurrentThread: NSManagedObjectContext
        {
        get
        {
            return NSThread.isMainThread() ? self.managedObjectContext : self.backgroundManagedObjectContext
        }
    }
    
    // MARK: - Initialisation
    
    public init(databaseFileName: String)
    {
        let modelURL = NSBundle.mainBundle().URLForResource("Model", withExtension: "momd")!
        managedObjectModel = NSManagedObjectModel(contentsOfURL: modelURL)!
        
        let documentsDirectory = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).last!
        let storeURL = documentsDirectory.URLByAppendingPathComponent(databaseFileName)
        
        persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        let optionsForLightweightMigrations = [NSMigratePersistentStoresAutomaticallyOption: true,
                                               NSInferMappingModelAutomaticallyOption: true]
        do
        {
            try persistentStoreCoordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: optionsForLightweightMigrations)
        }
        catch let error as NSError
        {
            NSLog("Something went wrong adding the persistent store: \(error.localizedDescription)")
            abort()
        }
        
        let coordinator = self.persistentStoreCoordinator
        managedObjectContext = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = coordinator
        
        backgroundManagedObjectContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        backgroundManagedObjectContext.parentContext = managedObjectContext
        
        super.init()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(contextHasChanged(_:)), name: NSManagedObjectContextDidSaveNotification, object: nil)
    }
    
    // MARK: - Context saving
    
    func contextHasChanged(notification: NSNotification)
    {
        guard notification.object as? NSManagedObjectContext != self.managedObjectContext else
        {
            return
        }
        
        if NSThread.isMainThread() == false
        {
            let selector = #selector(contextHasChanged(_:))
            self.performSelectorOnMainThread(selector, withObject: notification, waitUntilDone: true)
            return
        }
        
        self.managedObjectContext.mergeChangesFromContextDidSaveNotification(notification)
        self.saveContext()
    }
    
    func saveContext()
    {
        let moc = contextForCurrentThread
        if moc.hasChanges
        {
            moc.performBlock({
                do
                {
                    try moc.save()
                    NSNotificationCenter.defaultCenter().postNotificationName(NSManagedObjectContextDidSaveNotification, object: moc)
                }
                catch let error as NSError
                {
                    NSLog("\(#function): An error occurred.\n\(error.localizedDescription)")
                }
            })
        }
    }
    
    // MARK: - Object creation
    
    public func createObjectWithEntityName<T>(entityName: String, configurationBlock: (T) -> ()) -> T?
    {
        let moc = contextForCurrentThread
        var createdObject: T?
        
        moc.performBlockAndWait({
            guard let object = NSEntityDescription.insertNewObjectForEntityForName(entityName, inManagedObjectContext: moc) as? T else
            {
                return
            }
            configurationBlock(object)
            do
            {
                self.saveContext()
                createdObject = object
            }
        })
        return createdObject
    }
    
    // MARK: - Object getters
    
    func allObjectsWithEntityName<T: AnyObject>(entityName: String, completionBlock: [T]? -> Void)
    {
        let moc = contextForCurrentThread
        moc.performBlock({
            let fetchRequest = NSFetchRequest(entityName: entityName)
            do
            {
                let fetchedObjects = try moc.executeFetchRequest(fetchRequest)
                completionBlock(fetchedObjects as? [T])
            }
            catch let error as NSError
            {
                NSLog("\(#function): An error occurred.\n\(error.localizedDescription)")
                completionBlock(nil)
            }
        })
    }
    
    func getManagedObjectWithEntityName<T>(entityName: String, andPredicate predicate: NSPredicate?, completionBlock: T? -> Void)
    {
        let moc = contextForCurrentThread
        moc.performBlock({
            let request = NSFetchRequest(entityName: entityName)
            request.predicate = predicate
            do
            {
                let object = try moc.executeFetchRequest(request).first
                completionBlock(object as? T)
            }
            catch let error as NSError
            {
                NSLog("\(#function): An error occurred.\n\(error.localizedDescription)")
                completionBlock(nil)
            }
        })
    }
    
    // MARK: - Deletion
    
    func deleteAllObjectsWithEntityName(entityName: String)
    {
        let moc = contextForCurrentThread
        moc.performBlock({
            let fetchRequest = NSFetchRequest(entityName: entityName)
            do
            {
                let allObjects = try moc.executeFetchRequest(fetchRequest)
                for object in allObjects
                {
                    moc.deleteObject(object as! NSManagedObject)
                }
                self.saveContext()
            }
            catch let error as NSError
            {
                NSLog("\(#function): An error occurred.\n\(error.localizedDescription)")
            }
        })
    }
}
