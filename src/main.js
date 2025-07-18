const { createFFmpeg, fetchFile } = FFmpeg;
const ffmpeg = createFFmpeg({
  log: true,
  progress: ({ ratio }) => {
    if (currentProgressCallback) {
      currentProgressCallback(ratio);
    }
  },
});
const dropArea = document.getElementById("drop-area");
const fileElem = document.getElementById("fileElem");
const progress = document.getElementById("progress");
const downloads = document.getElementById("downloads");
const downloadAllBtn = document.getElementById("download-all");

let ogvFiles = []; // {filename, blob}
let thumbnailFiles = []; // {filename, blob}
let currentProgressCallback = null;

// Drag & drop handlers
dropArea.addEventListener("dragover", (e) => {
  e.preventDefault();
  dropArea.classList.add("dragover");
});
dropArea.addEventListener("dragleave", (e) => {
  e.preventDefault();
  dropArea.classList.remove("dragover");
});
dropArea.addEventListener("drop", (e) => {
  e.preventDefault();
  dropArea.classList.remove("dragover");
  handleFiles(e.dataTransfer.files);
});
fileElem.addEventListener("change", (e) => {
  handleFiles(e.target.files);
});

async function handleFiles(fileList) {
  if (!fileList.length) return;
  const files = Array.from(fileList).filter((f) => f.type === "video/mp4");
  if (!files.length) {
    progress.textContent = "Please select MP4 files only.";
    return;
  }
  progress.textContent = "Loading FFmpeg...";
  downloads.innerHTML = "";
  ogvFiles = [];
  thumbnailFiles = [];
  downloadAllBtn.style.display = "none";
  if (!ffmpeg.isLoaded()) await ffmpeg.load();

  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    progress.textContent = `Converting (${i + 1}/${files.length}): ${
      file.name
    }`;

    // Create progress bar for this file
    const fileProgress = document.createElement("div");
    fileProgress.className = "file-progress";
    fileProgress.innerHTML = `
            <h4 class="not-prose">${file.name}</h4>
            <div class="progress-bar">
              <div class="progress-fill"></div>
            </div>
            <div class="progress-text">Preparing...</div>
          `;
    downloads.appendChild(fileProgress);

    const progressFill = fileProgress.querySelector(".progress-fill");
    const progressText = fileProgress.querySelector(".progress-text");

    // Set up progress callback for this file
    currentProgressCallback = (ratio) => {
      const percentage = Math.round(ratio * 100);
      progressFill.style.width = `${percentage}%`;
      progressText.textContent = `${percentage}% complete`;
    };

    const inputName = `input${i}.mp4`;
    const outputOgvName = file.name.replace(/\.mp4$/i, ".ogv");
    const baseName = file.name.replace(/\.mp4$/i, "");
    const outputThumbnailName = `${baseName}-thumbnail.jpg`;

    try {
      progressText.textContent = "Loading file...";
      ffmpeg.FS("writeFile", inputName, await fetchFile(file));

      progressText.textContent = "Converting to OGV...";
      // Convert to OGV
      await ffmpeg.run(
        "-i",
        inputName,
        "-c:v",
        "libtheora",
        "-qscale:v",
        "5",
        "-c:a",
        "libvorbis",
        "-b:a",
        "128k",
        outputOgvName
      );

      progressText.textContent = "Creating thumbnail...";
      const ogvData = ffmpeg.FS("readFile", outputOgvName);
      const ogvBlob = new Blob([ogvData.buffer], { type: "video/ogg" });
      const ogvUrl = URL.createObjectURL(ogvBlob);
      const aOgv = document.createElement("a");
      aOgv.href = ogvUrl;
      aOgv.download = outputOgvName;
      aOgv.textContent = `Download ${outputOgvName}`;
      aOgv.className = "download-link text-sm";
      downloads.appendChild(aOgv);
      ogvFiles.push({ filename: outputOgvName, blob: ogvBlob });

      // Extract first frame as jpg
      // -ss 0 seeks to the first frame, -frames:v 1 extracts one frame
      await ffmpeg.run(
        "-i",
        inputName,
        "-ss",
        "0",
        "-frames:v",
        "1",
        outputThumbnailName
      );

      progressText.textContent = "Finalizing...";
      const thumbData = ffmpeg.FS("readFile", outputThumbnailName);
      const thumbBlob = new Blob([thumbData.buffer], {
        type: "image/jpeg",
      });
      const thumbUrl = URL.createObjectURL(thumbBlob);
      const aThumb = document.createElement("a");
      aThumb.href = thumbUrl;
      aThumb.download = outputThumbnailName;
      aThumb.textContent = `Download ${outputThumbnailName}`;
      aThumb.className = "download-link text-sm";
      downloads.appendChild(aThumb);
      thumbnailFiles.push({
        filename: outputThumbnailName,
        blob: thumbBlob,
      });

      // Clean up FS
      ffmpeg.FS("unlink", inputName);
      ffmpeg.FS("unlink", outputOgvName);
      ffmpeg.FS("unlink", outputThumbnailName);

      // Mark as complete
      progressFill.style.width = "100%";
      progressFill.style.backgroundColor = "#096";
      progressText.textContent = "Complete!";
    } catch (err) {
      progressFill.style.backgroundColor = "#C10008";
      progressText.textContent = `Error: ${err.message}`;
      const errMsg = document.createElement("div");
      errMsg.textContent = `Failed to convert ${file.name}: ${err.message}`;
      downloads.appendChild(errMsg);
    }
  }

  currentProgressCallback = null;
  progress.textContent = "All conversions complete!";
  if (ogvFiles.length > 0 || thumbnailFiles.length > 0) {
    downloadAllBtn.style.display = "flex";
  }
}

downloadAllBtn.addEventListener("click", async () => {
  if (!ogvFiles.length && !thumbnailFiles.length) return;
  downloadAllBtn.disabled = true;
  const initialButtonHtml = downloadAllBtn.innerHTML;
  downloadAllBtn.innerHTML = "<span>Zipping...</span>";
  const zip = new JSZip();
  ogvFiles.forEach(({ filename, blob }) => {
    zip.file(filename, blob);
  });
  thumbnailFiles.forEach(({ filename, blob }) => {
    zip.file(filename, blob);
  });
  const content = await zip.generateAsync({ type: "blob" });
  const url = URL.createObjectURL(content);
  const a = document.createElement("a");
  a.href = url;
  a.download = "converted_ogv_files_with_thumbnails.zip";
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  downloadAllBtn.disabled = false;
  downloadAllBtn.innerHTML = initialButtonHtml;
});
