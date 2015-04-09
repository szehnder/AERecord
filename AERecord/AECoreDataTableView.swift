//  MARK: - CoreData driven UITableViewController
class CoreDataTableViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    
    //
    //  Swift version of class originaly created for Stanford CS193p Winter 2013.
    //
    //  This class mostly just copies the code from NSFetchedResultsController's documentation page
    //  into a subclass of UITableViewController.
    //
    //  Just subclass this and set the fetchedResultsController.
    //  The only UITableViewDataSource method you'll HAVE to implement is tableView:cellForRowAtIndexPath:.
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
                tableView.reloadData()
            }
        }
    }
    
    // Causes the fetchedResultsController to refetch the data.
    // You almost certainly never need to call this.
    // The NSFetchedResultsController class observes the context
    //  (so if the objects in the context change, you do not need to call performFetch
    //   since the NSFetchedResultsController will notice and update the table automatically).
    // This will also automatically be called if you change the fetchedResultsController @property.
    func performFetch() {
        if let frc = fetchedResultsController {
            var error: NSError?
            if !frc.performFetch(&error) {
                if let err = error {
                    if kAERecordPrintLog {
                        println("Error occured in \(NSStringFromClass(self.dynamicType)) - function: \(__FUNCTION__) | line: \(__LINE__)\n\(err)")
                    }
                }
            }
            tableView.reloadData()
        }
    }
    
    // Turn this on before making any changes in the managed object context that
    //  are a one-for-one result of the user manipulating rows directly in the table view.
    // Such changes cause the context to report them (after a brief delay),
    //  and normally our fetchedResultsController would then try to update the table,
    //  but that is unnecessary because the changes were made in the table already (by the user)
    //  so the fetchedResultsController has nothing to do and needs to ignore those reports.
    // Turn this back off after the user has finished the change.
    // Note that the effect of setting this to NO actually gets delayed slightly
    //  so as to ignore previously-posted, but not-yet-processed context-changed notifications,
    //  therefore it is fine to set this to YES at the beginning of, e.g., tableView:moveRowAtIndexPath:toIndexPath:,
    //  and then set it back to NO at the end of your implementation of that method.
    // It is not necessary (in fact, not desirable) to set this during row deletion or insertion
    //  (but definitely for row moves).
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
    private var beganUpdates: Bool = false
    
    // MARK: NSFetchedResultsControllerDelegate
    
    func controllerWillChangeContent(controller: NSFetchedResultsController) {
        if !suspendAutomaticTrackingOfChangesInManagedObjectContext {
            tableView.beginUpdates()
            beganUpdates = true
        }
    }
    
    func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        if !suspendAutomaticTrackingOfChangesInManagedObjectContext {
            switch type {
            case .Insert:
                tableView.insertSections(NSIndexSet(index: sectionIndex), withRowAnimation: .Fade)
            case .Delete:
                tableView.deleteSections(NSIndexSet(index: sectionIndex), withRowAnimation: .Fade)
            default:
                return
            }
        }
    }
    
    func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        if !suspendAutomaticTrackingOfChangesInManagedObjectContext {
            switch type {
            case .Insert:
                tableView.insertRowsAtIndexPaths([newIndexPath!], withRowAnimation: .Fade)
            case .Delete:
                tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Fade)
            case .Update:
                tableView.reloadRowsAtIndexPaths([indexPath!], withRowAnimation: .Fade)
            case .Move:
                tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation: .Fade)
                tableView.insertRowsAtIndexPaths([newIndexPath!], withRowAnimation: .Fade)
            default:
                return
            }
        }
    }
    
    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        if beganUpdates {
            tableView.endUpdates()
        }
    }
    
    // MARK: UITableViewDataSource
    
    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return fetchedResultsController?.sections?.count ?? 0
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (fetchedResultsController?.sections?[section] as? NSFetchedResultsSectionInfo)?.numberOfObjects ?? 0
    }
    
    override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return (fetchedResultsController?.sections?[section] as? NSFetchedResultsSectionInfo)?.name
    }
    
    override func tableView(tableView: UITableView, sectionForSectionIndexTitle title: String, atIndex index: Int) -> Int {
        return fetchedResultsController?.sectionForSectionIndexTitle(title, atIndex: index) ?? 0
    }
    
    override func sectionIndexTitlesForTableView(tableView: UITableView) -> [AnyObject]! {
        return fetchedResultsController?.sectionIndexTitles
    }
    
}