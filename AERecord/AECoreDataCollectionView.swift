import CoreData
import UIKit

//  MARK: - CoreData driven UICollectionViewController
class CoreDataCollectionViewController: UICollectionViewController, NSFetchedResultsControllerDelegate {
    
    //
    //  Same concept as CoreDataTableViewController, but modified for use with UICollectionViewController.
    //
    //  This class mostly just copies the code from NSFetchedResultsController's documentation page
    //  into a subclass of UICollectionViewController.
    //
    //  Just subclass this and set the fetchedResultsController.
    //  The only UICollectionViewDataSource method you'll HAVE to implement is collectionView:cellForItemAtIndexPath.
    //  And you can use the NSFetchedResultsController method objectAtIndexPath: to do it.
    //
    //  Remember that once you create an NSFetchedResultsController, you CANNOT modify its @propertys.
    //  If you want new fetch parameters (predicate, sorting, etc.),
    //  create a NEW NSFetchedResultsController and set this class's fetchedResultsController @property again.
    //
    
    // The controller (this class fetches nothing if this is not set).
    var fetchedResultsController: NSFetchedResultsController? {
        didSet {
            if let frc = fetchedResultsController {
                if frc != oldValue {
                    frc.delegate = self
                    performFetch()
                }
            } else {
                collectionView?.reloadData()
            }
        }
    }
    
    // Causes the fetchedResultsController to refetch the data.
    // You almost certainly never need to call this.
    // The NSFetchedResultsController class observes the context
    //  (so if the objects in the context change, you do not need to call performFetch
    //   since the NSFetchedResultsController will notice and update the collection view automatically).
    // This will also automatically be called if you change the fetchedResultsController @property.
    func performFetch() {
        if let frc = fetchedResultsController {
            do {
                try frc.performFetch()
            } catch let error as NSError {
                if kAERecordPrintLog {
                    print("Error occured in \(NSStringFromClass(self.dynamicType)) - function: \(__FUNCTION__) | line: \(__LINE__)\n\(error)")
                }
            } catch _ {
                // FIXME: fatal?
            }
            collectionView?.reloadData()
        }
    }
    
    // Turn this on before making any changes in the managed object context that
    //  are a one-for-one result of the user manipulating cells directly in the collection view.
    // Such changes cause the context to report them (after a brief delay),
    //  and normally our fetchedResultsController would then try to update the collection view,
    //  but that is unnecessary because the changes were made in the collection view already (by the user)
    //  so the fetchedResultsController has nothing to do and needs to ignore those reports.
    // Turn this back off after the user has finished the change.
    // Note that the effect of setting this to NO actually gets delayed slightly
    //  so as to ignore previously-posted, but not-yet-processed context-changed notifications,
    //  therefore it is fine to set this to YES at the beginning of, e.g., collectionView:moveItemAtIndexPath:toIndexPath:,
    //  and then set it back to NO at the end of your implementation of that method.
    // It is not necessary (in fact, not desirable) to set this during row deletion or insertion
    //  (but definitely for cell moves).
    private var _suspendAutomaticTrackingOfChangesInManagedObjectContext: Bool = false
    var suspendAutomaticTrackingOfChangesInManagedObjectContext: Bool {
        get {
            return _suspendAutomaticTrackingOfChangesInManagedObjectContext
        }
        set (newValue) {
            if newValue == true {
                _suspendAutomaticTrackingOfChangesInManagedObjectContext = true
            } else {
                dispatch_after(0, dispatch_get_main_queue(), { self._suspendAutomaticTrackingOfChangesInManagedObjectContext = false })
            }
        }
    }
    
    // MARK: NSFetchedResultsControllerDelegate Helpers
    
    private var sectionInserts = [Int]()
    private var sectionDeletes = [Int]()
    private var sectionUpdates = [Int]()
    
    private var objectInserts = [NSIndexPath]()
    private var objectDeletes = [NSIndexPath]()
    private var objectUpdates = [NSIndexPath]()
    private var objectMoves = [NSIndexPath]()
    private var objectReloads = NSMutableSet()
    
    func updateSectionsAndObjects() {
        // sections
        if !self.sectionInserts.isEmpty {
            for sectionIndex in self.sectionInserts {
                self.collectionView?.insertSections(NSIndexSet(index: sectionIndex))
            }
            self.sectionInserts.removeAll(keepCapacity: true)
        }
        if !self.sectionDeletes.isEmpty {
            for sectionIndex in self.sectionDeletes {
                self.collectionView?.deleteSections(NSIndexSet(index: sectionIndex))
            }
            self.sectionDeletes.removeAll(keepCapacity: true)
        }
        if !self.sectionUpdates.isEmpty {
            for sectionIndex in self.sectionUpdates {
                self.collectionView?.reloadSections(NSIndexSet(index: sectionIndex))
            }
            self.sectionUpdates.removeAll(keepCapacity: true)
        }
        // objects
        if !self.objectInserts.isEmpty {
            self.collectionView?.insertItemsAtIndexPaths(self.objectInserts)
            self.objectInserts.removeAll(keepCapacity: true)
        }
        if !self.objectDeletes.isEmpty {
            self.collectionView?.deleteItemsAtIndexPaths(self.objectDeletes)
            self.objectDeletes.removeAll(keepCapacity: true)
        }
        if !self.objectUpdates.isEmpty {
            self.collectionView?.reloadItemsAtIndexPaths(self.objectUpdates)
            self.objectUpdates.removeAll(keepCapacity: true)
        }
        if !self.objectMoves.isEmpty {
            let moveOperations = objectMoves.count / 2
            var index = 0
            for _ in 0 ..< moveOperations {
                self.collectionView?.moveItemAtIndexPath(self.objectMoves[index], toIndexPath: self.objectMoves[index + 1])
                index = index + 2
            }
            self.objectMoves.removeAll(keepCapacity: true)
        }
    }
    
    // MARK: NSFetchedResultsControllerDelegate
    
    func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        switch type {
        case .Insert:
            sectionInserts.append(sectionIndex)
        case .Delete:
            sectionDeletes.append(sectionIndex)
        case .Update:
            sectionUpdates.append(sectionIndex)
        default:
            break
        }
    }
    
    func controller(controller: NSFetchedResultsController, didChangeObject anObject: NSManagedObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        switch type {
        case .Insert:
            objectInserts.append(newIndexPath!)
        case .Delete:
            objectDeletes.append(indexPath!)
        case .Update:
            objectUpdates.append(indexPath!)
        case .Move:
            objectMoves.append(indexPath!)
            objectMoves.append(newIndexPath!)
            objectReloads.addObject(indexPath!)
            objectReloads.addObject(newIndexPath!)
        }
    }
    
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        if !suspendAutomaticTrackingOfChangesInManagedObjectContext {
            // do batch updates on collection view
            collectionView?.performBatchUpdates({ () -> Void in
                self.updateSectionsAndObjects()
                }, completion: { (finished) -> Void in
                    // reload moved items when finished
                    if self.objectReloads.count > 0 {
                        self.collectionView?.reloadItemsAtIndexPaths(self.objectReloads.allObjects as! [NSIndexPath])
                        self.objectReloads.removeAllObjects()
                    }
            })
        }
    }
    
    // MARK: UICollectionViewDataSource
    
    override func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return fetchedResultsController?.sections?.count ?? 0
    }
    
    override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if (fetchedResultsController != nil && fetchedResultsController!.sections != nil) {
            let sectionInfo = fetchedResultsController!.sections![section]
            return sectionInfo.numberOfObjects
        }
        return 0
    }
    
}