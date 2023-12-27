---
layout: page
title: Imago
permalink: /projects/imago
---

<br>

![imago example still](/assets/img/projects/imago-still-1-512.jpg){: .center-image width="400px" }


### imago


Polli's spiritual predecessor. Rudimentary computer vision pipeline to infer pollination activity from images & video.

Quickly developed to accelerate my Summer 2021 fieldwork, allowing me to collect ~100x more data than I could have manually. The study would have been impossible to conduct with manual sampling with a single part-time field assistant, so I built something to offload the inefficient parts of fieldwork. 

Pipeline sensitivity was much more important than computational efficiency, and I didn't have the time to develop a research-grade detection model. I had the insight that a sufficiently generalized classifier can function as a detector when passed over many overlapping slices of an image. *imago* recursively applies a general taxonomic classifier to image slices, aggregates & then filters results with per-class NMS, and then infers floral visitations with the reconstructed bounding boxes.

Produced as part of my (unsubmitted) MSc [thesis](/assets/doc/imago-ch2-draft-7.0.pdf) at Kansas State University.

<br>

I may eventually open-source this codebase as a historical curiosity, but it is very ugly.