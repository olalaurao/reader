-- SPDX-License-Identifier: AGPL-3.0-only

local ArticleUI = require("ui/article")
local AnnotationDiagnosticsUI = require("ui/annotation_diagnostics")
local AnnotationUploadUI = require("ui/annotation_upload")
local ApiInteropUI = require("ui/api_interop")
local Config = require("config")
local Constants = require("constants")
local DB = require("storage/db")
local AnnotationsRepository = require("storage/annotations")
local DocumentsRepository = require("storage/documents")
local Filenames = require("content/filenames")
local FirstArticle = require("sync/first_article")
local Hash = require("content/hash")
local Html = require("content/html")
local Images = require("content/images")
local Http = require("api/http")
local Installer = require("content/installer")
local RawSource = require("content/raw_source")
local KOReaderCollections = require("koreader/collections")
local KOReaderDocuments = require("koreader/documents")
local KOReaderAnnotations = require("koreader/annotations")
local Reader = require("api/reader")
local Metadata = require("sync/metadata")
local AnnotationSync = require("sync/annotations")
local AnnotationUpload = require("sync/annotation_upload")
local LibraryUI = require("ui/library")
local SettingsUI = require("ui/settings")
local SyncMeta = require("storage/sync_meta")
local SyncUI = require("ui/sync")
local ImageSpikeUI = require("ui/image_spike")
local RawFormatUI = require("ui/raw_format")
local TagDiagnosticsUI = require("ui/tag_diagnostics")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ReadwiseReader = WidgetContainer:extend{
    name = "readwisereader",
    is_doc_only = false,
    version = Constants.VERSION,
}

function ReadwiseReader:init()
    self.config = Config:new()
    self.http = Http:new()
    self.reader_api = Reader:new{
        http = self.http,
        config = self.config,
    }
    self.db = DB:new()
    self.documents_repository = DocumentsRepository:new{
        db = self.db,
    }
    self.annotations_repository = AnnotationsRepository:new{
        db = self.db,
    }
    self.sync_meta = SyncMeta:new{
        db = self.db,
    }
    self.koreader_documents = KOReaderDocuments:new()
    self.koreader_annotations = KOReaderAnnotations:new{
        hasher = Hash,
    }
    self.koreader_collections = KOReaderCollections:new()
    self.annotation_scanner = AnnotationSync:new{
        documents = self.documents_repository,
        annotations = self.annotations_repository,
        adapter = self.koreader_annotations,
    }
    local installer = Installer:new()
    self.first_article = FirstArticle:new{
        reader = self.reader_api,
        repository = self.documents_repository,
        html = Html,
        images = Images:new{
            http = self.http,
            installer = installer,
            enabled = self.config:getDownloadImages(),
            per_image_max = self.config:getMaxImageBytes(),
            total_max = self.config:getMaxArticleImageBytes(),
            max_images = self.config:getMaxImagesPerArticle(),
        },
        raw_source = RawSource:new{
            http = self.http,
            installer = installer,
            download_root = self.config:getDownloadDirectory(),
            max_bytes = self.config:getMaxRawSourceBytes(),
            min_free_bytes = self.config:getMinRawSourceFreeBytes(),
        },
        filenames = Filenames,
        installer = installer,
        hasher = Hash,
        koreader_documents = self.koreader_documents,
        download_root = self.config:getDownloadDirectory(),
    }
    self.article_ui = ArticleUI:new{
        config = self.config,
        coordinator = self.first_article,
        koreader_documents = self.koreader_documents,
    }
    self.metadata_scanner = Metadata:new{
        reader = self.reader_api,
    }
    self.library_ui = LibraryUI:new{
        config = self.config,
        scanner = self.metadata_scanner,
    }
    self.settings_ui = SettingsUI:new{
        config = self.config,
        reader = self.reader_api,
    }
    self.sync_ui = SyncUI:new{
        config = self.config,
        sync_meta = self.sync_meta,
        collections = self.koreader_collections,
        koreader_documents = self.koreader_documents,
    }
    self.tag_diagnostics_ui = TagDiagnosticsUI:new{
        config = self.config,
    }
    self.image_spike_ui = ImageSpikeUI:new{
        config = self.config,
        installer = Installer:new(),
        koreader_documents = self.koreader_documents,
    }
    self.raw_format_ui = RawFormatUI:new{
        config = self.config,
        koreader_documents = self.koreader_documents,
        collections = self.koreader_collections,
    }
    self.annotation_diagnostics_ui = AnnotationDiagnosticsUI:new{
        scanner = self.annotation_scanner,
        get_current_path = function()
            return self.ui and self.ui.document and self.ui.document.file or nil
        end,
    }
    self.annotation_uploader = AnnotationUpload:new{
        documents = self.documents_repository,
        annotations = self.annotations_repository,
        adapter = self.koreader_annotations,
        reader = self.reader_api,
        hasher = Hash,
    }
    self.annotation_upload_ui = AnnotationUploadUI:new{
        uploader = self.annotation_uploader,
        get_current_path = function()
            return self.ui and self.ui.document and self.ui.document.file or nil
        end,
    }
    self.api_interop_ui = ApiInteropUI:new{
        config = self.config,
    }
    self.ui.menu:registerToMainMenu(self)
end

function ReadwiseReader:addToMainMenu(menu_items)
    menu_items.readwisereader = {
        text = _("Readwise Reader"),
        sorting_hint = "more_tools",
        sub_item_table = {
            self.sync_ui:getSyncMenuItem(),
            self.sync_ui:getStatusMenuItem(),
            self.sync_ui:getFullRescanMenuItem(),
            self.article_ui:getMenuItem(),
            self.library_ui:getScanMenuItem(),
            self.tag_diagnostics_ui:getMenuItem(),
            self.image_spike_ui:getMenuItem(),
            self.raw_format_ui:getMenuItem(),
            self.annotation_diagnostics_ui:getMenuItem(),
            self.annotation_upload_ui:getMenuItem(),
            self.api_interop_ui:getMenuItem(),
            self.settings_ui:getSettingsMenu(),
        },
    }
end

function ReadwiseReader:onCloseWidget()
    if self.db then
        self.db:close()
    end
    if self.config then
        self.config:close()
    end
end

return ReadwiseReader
