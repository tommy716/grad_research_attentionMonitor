//
//  ResultsViewController.swift
//  concentrationMonitor
//
//  Created by Tommy on 2021/11/09.
//

import UIKit

class ResultsViewController: UIViewController {
    
    @IBOutlet var resultLabel: UILabel!
    @IBOutlet var detailResultLabel: UILabel!
    @IBOutlet var concentrationTimeLabel: UILabel!
    @IBOutlet var totalTimeLabel: UILabel!
    
    var concentrationResults: [Int]?
    var detailedResults: [Double]?
    var resultsForCSV: [String]?
    var concentrationTime: Double!
    var totalTime: Double!
    
    var dateString = ""
    var documentInteraction: UIDocumentInteractionController!

    override func viewDidLoad() {
        super.viewDidLoad()
        print("Concentration Results: ", concentrationResults)
        if concentrationResults != nil {
            let result = (Double(concentrationResults!.reduce(0, +)) / Double(concentrationResults!.count)) * 100
            resultLabel.text = String(format: "%.2f", result) + "%"
        } else {
            resultLabel.text = "Error"
        }
        
        if concentrationResults != nil {
            let result = (detailedResults!.reduce(0.0, +) / Double(detailedResults!.count)) * 100
            detailResultLabel.text = String(format: "%.2f", result) + "%"
        } else {
            detailResultLabel.text = "Error"
        }
        
        if concentrationTime != nil {
            concentrationTimeLabel.text = "Concentrated: " + String(format: "%.5f", concentrationTime) + "s"
        } else {
            detailResultLabel.text = "Error"
        }
        
        if totalTime != nil {
            totalTimeLabel.text = "Total: " + String(format: "%.5f", totalTime) + "s"
        } else {
            totalTimeLabel.text = "Error"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMd-Hms"
        dateString = dateFormatter.string(from: Date())
    }
    
    @IBAction func exportCSV() {
        guard let results = resultsForCSV else {
            let alert: UIAlertController = UIAlertController(title: "Error", message: "Results are missing", preferredStyle: .alert)
            let okAction: UIAlertAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            alert.addAction(okAction)
            self.present(alert, animated: true, completion: nil)
            return
        }
        var fileStrData = "timeStamp,concentration,probability\n"
        
        for data in results {
            fileStrData += data
            fileStrData += "\n"
        }
        
        createFile("\(dateString)_validation.csv", fileStrData)
    }
    
    @IBAction func donePressed() {
        self.presentingViewController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    func createFile(_ fileName: String, _ fileStrData: String){
        let documentDirectoryFileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        let FilePath = documentDirectoryFileURL.appendingPathComponent(fileName)
        
        do {
            try fileStrData.prefix(fileStrData.count - 2).write(to: FilePath, atomically: true, encoding: String.Encoding.utf8)
        } catch let error as NSError {
            print("failed to write: \(error)")
        }
        
        documentInteraction = UIDocumentInteractionController()
        documentInteraction.url = FilePath
        
        if !(documentInteraction.presentOpenInMenu(from:  CGRect(x: 0, y: 0, width: 10, height: 10), in: self.view, animated: true)) {
            let alert = UIAlertController(title: "Failed to send", message: "Cannot find available apps", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
}
