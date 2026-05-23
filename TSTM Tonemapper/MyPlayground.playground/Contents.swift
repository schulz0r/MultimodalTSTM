import TSTM_Tonemapper
import CoreImage

let url = URL(fileURLWithPath: "/Users/phiilppwaxweiler.de/Desktop/input.tiff")
guard let inputImage = CIImage(contentsOf: url) else { fatalError("Failed to load image") }

let nakaRushton = TSTMTonemapper()
nakaRushton.inputImage = inputImage

let contrastFilter = ContrastEnhancement()
contrastFilter.inputImage = nakaRushton.outputImage!
