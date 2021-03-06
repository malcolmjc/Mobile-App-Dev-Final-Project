//
//  ARViewController.swift
//  Brouhaha
//
//  Created by Malcolm Craney on 3/2/19.
//  Copyright © 2019 Malcolm Craney. All rights reserved.
//
// Credit to https://github.com/Rageeni/AR-Drawing
// And https://www.appcoda.com/arkit-persistence/
// For helping me in my design and creation of the AR component

import UIKit
import ARKit
import Firebase
import FirebaseDatabase
import RGSColorSlider
import AVFoundation
import CoreLocation
import GeoFire

enum ShapeType {
    case sphere
    case plane
    case ring
    case pyramid
    case box
}

class ARViewController: UIViewController, ARSCNViewDelegate, CLLocationManagerDelegate {

    @IBOutlet weak var sceneView: ARSCNView!
    
    @IBOutlet weak var sprayPaintCan: UIButton!
    var databaseRef : DatabaseReference!
    var storage: Storage!
    
    var isDraw: Bool = false
    var nodeWidth: CGFloat! = 3
    var nodeColor: UIColor! = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1)
    
    let strokeTextAttributes: [NSAttributedString.Key : Any] = [
        .strokeColor: UIColor.black,
        .foregroundColor: UIColor.white,
        .strokeWidth: -2.0
    ]
    
    var player: AVAudioPlayer?
    
    var selectedAlpha: CGFloat = 0.7
    
    var locationManager = CLLocationManager()
    var geoFire : GeoFire?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        sceneView.delegate = self
        configureLighting()
        
        //set up spray paint can so it's top is midway in the arscene view
        let heightConstraint = NSLayoutConstraint(item: sprayPaintCan, attribute: NSLayoutConstraint.Attribute.height,
                                                  relatedBy: NSLayoutConstraint.Relation.equal, toItem: nil,
                                                  attribute: NSLayoutConstraint.Attribute.notAnAttribute, multiplier: 1,
                                                  constant: sceneView.bounds.size.height / 2.25)
        view.addConstraints([heightConstraint])
        
        shapeButtons = [pyramidButton, cubeButton, planeButton, ringButton, sphereButton]
        
        let attrString = NSAttributedString(string: "Go back", attributes: strokeTextAttributes)
        editCancelButton.setAttributedTitle(attrString, for: .normal)
        
        sphereButton.alpha = selectedAlpha
        self.becomeFirstResponder()
        
        databaseRef = Database.database().reference().child("ARPosts")
        storage = Storage.storage()
        
        locationManager.delegate = self
    }
    
    override var canBecomeFirstResponder: Bool {
        get { return true }
    }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        /*if motion == .motionShake {
            playSound(name: "shake")
        }*/
    }
    
    @IBOutlet weak var colorSlider: RGSColorSlider!
    @IBOutlet weak var lineWidthSlider: UISlider!
    
    @IBOutlet weak var editCancelButton: UIButton!
    var isInEditMode: Bool = false {
        didSet {
            if isInEditMode == false {
                if let pointer = self.pointerNode {
                    pointer.removeFromParentNode()
                }
            }
        }
    }

    @IBAction func changePaintPressed(_ sender: Any) {
        isInEditMode = true
        
        colorSlider.isHidden = false
        lineWidthSlider.isHidden = false
        editCancelButton.isHidden = false
        sprayPaintCan.isHidden = true
        undoButton.isHidden = true
        editButton.isHidden = true
        saveButton.isHidden = true
        for btn in shapeButtons {
            btn.isHidden = false
        }
    }
    
    @IBAction func savePressed(_ sender: Any) {
        let userCoords = locationManager.location!.coordinate
        sceneView.session.getCurrentWorldMap { (worldMap, error) in
            guard let worldMap = worldMap else {
                return
            }
            
            //take screenshot, then archive data to firebase
            do {
                try self.takeScreenshot(worldMap: worldMap, coordinate: userCoords)
            } catch {
                fatalError("Error saving world map: \(error.localizedDescription)")
            }
        }
    }
    
    @IBOutlet weak var undoButton: UIButton!
    @IBOutlet weak var saveButton: UIButton!
    @IBOutlet weak var editButton: UIButton!
    
    @IBAction func undoPressed(_ sender: Any) {
        if mostRecentlyMadeNodes.count >= 1 {
            DispatchQueue.main.async {
                for node in self.mostRecentlyMadeNodes[0] {
                    node.removeFromParentNode()
                }
                self.mostRecentlyMadeNodes.remove(at: 0)
            }
        }
    }
    
    @IBAction func editCancellPressed(_ sender: Any) {
        isInEditMode = false
        
        colorSlider.isHidden = true
        lineWidthSlider.isHidden = true
        editCancelButton.isHidden = true
        sprayPaintCan.isHidden = false
        undoButton.isHidden = false
        editButton.isHidden = false
        saveButton.isHidden = false
        for btn in shapeButtons {
            btn.isHidden = true
        }
    }
    
    @IBAction func lineWidthSliderChangedValue(_ sender: Any) {
        nodeWidth = CGFloat((sender as? UISlider)!.value)
    }
    
    @IBAction func colorWidthSliderChangedValue(_ sender: Any) {
        let colorSlider = sender as? RGSColorSlider
        nodeColor = colorSlider!.color!
    }
    
    @IBAction func canTouchedDown(_ sender: Any) {
        mostRecentlyMadeNodes.insert([SCNNode](), at: 0)
        isDraw = true
        //playSound(name: "spray")
    }
    
    @IBAction func canDoneTouched(_ sender: Any) {
        isDraw = false
        /*if player?.isPlaying ?? false {
            player!.stop()
        }*/
    }
    
    func milesToMeters(miles: Double) -> Double {
        return miles * 1609.34
    }
    
    //var potentialWorldMaps: ARWorldMap[] = []
    func getStartingWorldMapData() {
        var worldMap: ARWorldMap?
        let regionQuery = geoFire?.query(at: locationManager.location!, withRadius: milesToMeters(miles: 0.1))
        regionQuery?.observe(.keyEntered, with: { (key, location) in
            print("observing")
            self.databaseRef?.queryOrderedByKey().queryEqual(toValue: key).observe(.value, with: { snapshot in
                print("in query")
                let arAnno = ARAnnotation(key:key, snapshot:snapshot)
                let httpsReference = self.storage.reference(forURL: arAnno.worldMapDataLink as? String ?? "error")
                
                httpsReference.getData(maxSize: 3 * 1024 * 1024) { data, error in
                    if let error = error {
                        print("could not get nearby world map - instead starting with none")
                        self.resetTrackingConfiguration(with: nil)
                    } else {
                        worldMap = self.unarchiveData(worldMapData: data!)
                        self.resetTrackingConfiguration(with: nil)
                    }
                }
            })
            print("done w/ observing")
        })
        self.resetTrackingConfiguration(with: nil)
    }
    
    var mostRecentlyMadeNodes = [[SCNNode]]()
    var pointerNode: SCNNode?
    var chosenShape: ShapeType = .sphere
    
    func clearButtonOpacities() {
        for btn in shapeButtons {
            btn.alpha = 1.0
        }
    }
    
    @IBAction func sphereButtonPressed(_ sender: Any) {
        chosenShape = .sphere
        clearButtonOpacities()
        sphereButton.alpha = selectedAlpha
    }
    
    @IBAction func planeButtonPressed(_ sender: Any) {
        chosenShape = .plane
        clearButtonOpacities()
        planeButton.alpha = selectedAlpha
    }
    
    @IBAction func ringButtonPressed(_ sender: Any) {
        chosenShape = .ring
        clearButtonOpacities()
        ringButton.alpha = selectedAlpha
    }
    
    @IBAction func pyramidButtonPressed(_ sender: Any) {
        chosenShape = .pyramid
        clearButtonOpacities()
        pyramidButton.alpha = selectedAlpha
    }
    
    @IBAction func cubeButtonPressed(_ sender: Any) {
        chosenShape = .box
        clearButtonOpacities()
        cubeButton.alpha = selectedAlpha
    }
    
    @IBOutlet weak var pyramidButton: UIButton!
    @IBOutlet weak var cubeButton: UIButton!
    @IBOutlet weak var planeButton: UIButton!
    @IBOutlet weak var ringButton: UIButton!
    @IBOutlet weak var sphereButton: UIButton!
    var shapeButtons: [UIButton] = []

    func getCurrentNodeType(_ width: CGFloat) -> SCNNode {
        var node: SCNNode
        
        switch chosenShape {
        case .box:
            node = SCNNode(geometry: SCNBox(width: width, height: width, length: width, chamferRadius: 0.0))
        case .pyramid:
            node = SCNNode(geometry: SCNPyramid(width: width, height: width*2, length: width))
        case .ring:
            node = SCNNode(geometry: SCNTorus(ringRadius: width, pipeRadius: width/4))
        case .plane:
            node = SCNNode(geometry: SCNPlane(width: width, height: width))
        default:
            node = SCNNode(geometry: SCNSphere(radius: width))
        }
        
        return node
    }
    
    func displayNode(_ node: SCNNode) {
        //user is drawing
        if isDraw {
            mostRecentlyMadeNodes[0].append(node)
            sceneView.scene.rootNode.addChildNode(node)
            
            /*if let player = player {
                if !player.isPlaying {
                    player.play()
                } else if player.currentTime >= 1.5 {
                    player.stop()
                    player.currentTime = 0.0
                    player.play()
                }
            }*/
        }
            
        //user is editing, show them a pointer of what they will paint
        else {
            DispatchQueue.main.async {
                if let pointer = self.pointerNode {
                    pointer.removeFromParentNode()
                }
                self.pointerNode = node
                self.sceneView.scene.rootNode.addChildNode(node)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {
        guard let pointOfView = sceneView.pointOfView else { return }
        //this should not happen but just in case
        if !isDraw && !isInEditMode { return }
        
        let transform = pointOfView.transform
        let orientation = SCNVector3(x: -transform.m31, y: -transform.m32, z: -transform.m33)
        let location = SCNVector3(x: transform.m41, y: transform.m42, z: transform.m43)
        let currentPosition = orientation + location
        
        let width = nodeWidth/200
        
        let node: SCNNode = getCurrentNodeType(width)
    
        node.geometry?.firstMaterial?.diffuse.contents = nodeColor
        node.position = currentPosition
        
        displayNode(node)
    }
    
    func configureLighting() {
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        getStartingWorldMapData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    func resetTrackingConfiguration(with worldMap: ARWorldMap?) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        
        let options: ARSession.RunOptions = [.resetTracking, .removeExistingAnchors]
        
        if worldMap != nil {
            print("\n\nsetting world map to be decoded map\n\n")
            configuration.initialWorldMap = worldMap
        }
        
        sceneView.session.run(configuration, options: options)
    }
    
    func unarchiveData(worldMapData data: Data) -> ARWorldMap? {
        guard let unarchievedObject = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data),
            let worldMap = unarchievedObject else { return nil }
        
        return worldMap
    }
    
    var addedAnnotations: [ARAnnotation] = []
    func archiveData(worldMap: ARWorldMap, coordinate: CLLocationCoordinate2D) throws {
        let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
        let storageRef = storage.reference()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let dateCreated = NSDate()
        let dateCreatedStr = formatter.string(from: dateCreated as Date)
        
        // Create a reference to the file you want to upload
        let arpostRef = storageRef.child(dateCreatedStr)
        
        let uploadTask = arpostRef.putData(data, metadata: nil) { (metadata, error) in
            guard let metadata = metadata else {
                // Uh-oh, an error occurred!
                return
            }
            
            // You can also access to download URL after upload.
            arpostRef.downloadURL { (url, error) in
                if let downloadURL = url {
                    print(downloadURL.absoluteString)
                    let newAnnotation = ARAnnotation(
                                                 dateCreated: dateCreatedStr,
                                                 imageLink: self.imageDownloadUrl,
                                                 worldMapDataLink: downloadURL.absoluteString,
                                                 latitude: coordinate.latitude,
                                                 longitude: coordinate.longitude)
                    self.geoFire?.setLocation(CLLocation(latitude: newAnnotation.latitude,
                                             longitude: newAnnotation.longitude),
                                             forKey: newAnnotation.dateCreated)
                    self.addedAnnotations.append(newAnnotation)
                    
                    self.databaseRef.child(newAnnotation.dateCreated)
                        .setValue(newAnnotation.toAnyObject())
                } else {
                    print(error.debugDescription)
                    return
                }
            }
        }
    }
    
    var imageDownloadUrl = "n/a"
    func takeScreenshot(worldMap: ARWorldMap, coordinate: CLLocationCoordinate2D) throws {
        let data = self.sceneView.snapshot().pngData()
        let storageRef = storage.reference()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let dateCreated = NSDate()
        let dateCreatedStr = formatter.string(from: dateCreated as Date)
        
        // Create a reference to the file you want to upload
        let arpostRef = storageRef.child(dateCreatedStr)
        
        //upload the data
        if let data = data {
            DispatchQueue.main.async {
                // Briefly flash the screen.
                let flashOverlay = UIView(frame: self.sceneView.frame)
                flashOverlay.backgroundColor = UIColor.white
                self.sceneView.addSubview(flashOverlay)
                UIView.animate(withDuration: 0.25, animations: {
                    flashOverlay.alpha = 0.0
                }, completion: { _ in
                    flashOverlay.removeFromSuperview()
                })
            }
            
            let uploadTask = arpostRef.putData(data, metadata: nil) { (metadata, error) in
                guard let metadata = metadata else {
                    // Uh-oh, an error occurred!
                    return
                }
                
                // You can also access to download URL after upload.
                arpostRef.downloadURL { (url, error) in
                    if let downloadURL = url {
                        self.imageDownloadUrl = downloadURL.absoluteString
                        do {
                            try self.archiveData(worldMap: worldMap, coordinate: coordinate)
                        }
                        catch {
                            print("error archiving world map data")
                        }
                    } else {
                        print(error.debugDescription)
                        self.imageDownloadUrl = "n/a"
                    }
                }
            }
        }
        else {
            self.imageDownloadUrl = "n/a"
        }
    }
    
    func playSound(name: String) {
        guard let url = Bundle.main.url(forResource: "sound/" + name, withExtension: "wav") else { return }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            //allows player to work on ios11
            self.player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.wav.rawValue)
            
            guard let player = self.player else { return }
            
            player.play()
            
        } catch let error {
            print(error.localizedDescription)
        }
    }
    
    @IBAction func cancelIconPressed(_ sender: Any) {
        performSegue(withIdentifier: "unwindToMap", sender: self)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "unwindToMap" {
            let destVC = segue.destination as? MapViewController
            for anno in addedAnnotations {
                destVC?.addNewARAnnotation(anno)
            }
        }
    }
}

func +(left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x + right.x, left.y + right.y, left.z + right.z)
}

func ==(left: SCNVector3, right: SCNVector3) -> Bool {
    if String(format: "%.1f", left.x) == String(format: "%.1f", right.x) {
        if String(format: "%.1f", left.y) == String(format: "%.1f", right.y) {
            if String(format: "%.1f", left.z) == String(format: "%.1f", right.z) {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    } else {
        return false
    }
}

extension float4x4 {
    var translation: float3 {
        let translation = self.columns.3
        return float3(translation.x, translation.y, translation.z)
    }
}
