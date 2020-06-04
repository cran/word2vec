#' @title Train a word2vec model on text
#' @description Construct a word2vec model on text. The algorithm is explained at \url{https://arxiv.org/pdf/1310.4546.pdf}
#' @param x a character vector with text or the path to the file on disk containing training data
#' @param type the type of algorithm to use, either 'cbow' or 'skip-gram'. Defaults to 'cbow'
#' @param dim dimension of the word vectors. Defaults to 50.
#' @param iter number of training iterations. Defaults to 5.
#' @param lr initial learning rate also known as alpha. Defaults to 0.05
#' @param window skip length between words. Defaults to 5.
#' @param hs logical indicating to use hierarchical softmax instead of negative sampling. Defaults to FALSE indicating to do negative sampling.
#' @param negative integer with the number of negative samples. Only used in case hs is set to FALSE
#' @param sample threshold for occurrence of words. Defaults to 0.001
#' @param min_count integer indicating the number of time a word should occur to be considered as part of the training vocabulary. Defaults to 5.
#' @param split a character vector of length 2 where the first element indicates how to split words and the second element indicates how to split sentences in \code{x}
#' @param stopwords a character vector of stopwords to exclude from training 
#' @param threads number of CPU threads to use. Defaults to 1.
#' @return an object of class \code{w2v_trained} which is a list with elements 
#' \itemize{
#' \item{model: a Rcpp pointer to the model}
#' \item{data: a list with elements file: the training data used, stopwords: the character vector of stopwords, n}
#' \item{vocabulary: the number of words in the vocabulary}
#' \item{success: logical indicating if training succeeded}
#' \item{error_log: the error log in case training failed}
#' \item{control: as list of the training arguments used, namely min_count, dim, window, iter, lr, skipgram, hs, negative, sample, split_words, split_sents, expTableSize and expValueMax}
#' }
#' @references \url{https://github.com/maxoodf/word2vec}
#' @export
#' @examples
#' library(udpipe)
#' ## Take data and standardise it a bit
#' data(brussels_reviews, package = "udpipe")
#' x <- subset(brussels_reviews, language == "nl")
#' x <- tolower(x$feedback)
#' 
#' ## Build the model get word embeddings and nearest neighbours
#' model <- word2vec(x = x, dim = 15, iter = 20)
#' emb   <- as.matrix(model)
#' head(emb)
#' emb <- predict(model, c("bus", "toilet", "unknownword"), type = "embedding")
#' emb
#' nn  <- predict(model, c("bus", "toilet"), type = "nearest", top_n = 5)
#' nn
#' 
#' ## Get vocabulary
#' vocab <- summary(model, type = "vocabulary")
#' 
#' ## Save the model to hard disk
#' path <- "mymodel.bin"
#' \dontshow{
#' path <- tempfile(pattern = "w2v", fileext = ".bin")
#' }
#' write.word2vec(model, file = path)
#' model <- read.word2vec(path)
#' 
#' \dontshow{
#' file.remove(path)
#' }
word2vec <- function(x,
                     type = c("cbow", "skip-gram"),
                     dim = 50, window = 5L, 
                     iter = 5L, lr = 0.05, hs = FALSE, negative = 5L, sample = 0.001, min_count = 5L, 
                     split = c(" \n,.-!?:;/\"#$%&'()*+<=>@[]\\^_`{|}~\t\v\f\r", 
                               ".\n?!"),
                     stopwords = character(),
                     threads = 1L){
    type <- match.arg(type)
    stopw <- stopwords
    model <- file.path(tempdir(), "w2v.bin")
    if(length(stopw) == 0){
        stopw <- ""
    }
    file_stopwords <- tempfile()
    writeLines(stopw, file_stopwords)
    on.exit({
        if (file.exists(file_stopwords)) file.remove(file_stopwords)
    })
    if(length(x) == 1){
         file_train <- x
    }else{
        file_train <- tempfile(pattern = "textspace_", fileext = ".txt")
        on.exit({
            if (file.exists(file_stopwords)) file.remove(file_stopwords)
            if (file.exists(file_train)) file.remove(file_train)
        })
        writeLines(text = x, con = file_train)  
    }
    
    
    expTableSize <- 1000L
    expValueMax <- 6L
    min_count <- as.integer(min_count)
    dim <- as.integer(dim)
    window <- as.integer(window)
    iter <- as.integer(iter)
    expTableSize <- as.integer(expTableSize)
    expValueMax <- as.integer(expValueMax)
    sample <- as.numeric(sample)
    hs <- as.logical(hs)
    negative <- as.integer(negative)
    threads <- as.integer(threads)
    iter <- as.integer(iter)
    lr <- as.numeric(lr)
    skipgram <- as.logical(type %in% "skip-gram")
    split <- as.character(split)
    model <- w2v_train(trainFile = file_train, modelFile = model, stopWordsFile = file_stopwords,
                       minWordFreq = min_count,
                       size = dim, window = window, expTableSize = expTableSize, expValueMax = expValueMax, 
                       sample = sample, withHS = hs, negative = negative, threads = threads, iterations = iter,
                       alpha = lr, withSG = skipgram, wordDelimiterChars = split[1], endOfSentenceChars = split[2])
    model$data$stopwords <- stopwords
    model
}



#' @export
as.matrix.w2v <- function(x, ...){
    words <- w2v_dictionary(x$model)
    x <- w2v_embedding(x$model, words)
    x 
}

#' @export
as.matrix.w2v_trained <- function(x, ...){
    as.matrix.w2v(x)
}


#' @title Save a word2vec model to disk
#' @description Save a word2vec model as a binary file to disk or as a text file
#' @param x an object of class \code{w2v} or \code{w2v_trained} as returned by \code{\link{word2vec}}
#' @param file the path to the file where to store the model
#' @param type either 'bin' or 'txt' to write respectively the file as binary or as a text file. Defaults to 'bin'.
#' @return a logical indicating if the save process succeeded
#' @export
#' @seealso \code{\link{word2vec}}
#' @examples 
#' path  <- system.file(package = "word2vec", "models", "example.bin")
#' model <- read.word2vec(path)
#' 
#' 
#' ## Save the model to hard disk as a binary file
#' path <- "mymodel.bin"
#' \dontshow{
#' path <- tempfile(pattern = "w2v", fileext = ".bin")
#' }
#' write.word2vec(model, file = path)
#' \dontshow{
#' file.remove(path)
#' }
#' ## Save the model to hard disk as a text file (uses package udpipe)
#' library(udpipe)
#' path <- "mymodel.txt"
#' \dontshow{
#' path <- tempfile(pattern = "w2v", fileext = ".txt")
#' }
#' write.word2vec(model, file = path, type = "txt")
#' \dontshow{
#' file.remove(path)
#' }
write.word2vec <- function(x, file, type = c("bin", "txt")){
    type <- match.arg(type)
    stopifnot(inherits(x, "w2v_trained") || inherits(x, "w2v"))
    if(type == "bin"){
        w2v_save_model(x$model, file)
    }else if(type == "txt"){
        requireNamespace(package = "udpipe")
        wordvectors <- as.matrix(x)
        wv <- udpipe::as_word2vec(wordvectors)
        f <- base::file(file, open = "wt", encoding = "UTF-8")
        cat(wv, file = f)
        close(f)
        file.exists(file)
    }
}

#' @title Read a binary word2vec model from disk
#' @description Read a binary word2vec model from disk
#' @param file the path to the model file
#' @return an object of class w2v which is a list with elements
#' \itemize{
#' \item{model: a Rcpp pointer to the model}
#' \item{model_path: the path to the model on disk}
#' \item{dim: the dimension of the embedding matrix}
#' \item{n: the number of words in the vocabulary}
#' }
#' @export
#' @examples
#' path  <- system.file(package = "word2vec", "models", "example.bin")
#' model <- read.word2vec(path)
#' vocab <- summary(model, type = "vocabulary")
#' emb <- predict(model, c("bus", "naar", "unknownword"), type = "embedding")
#' emb
#' nn  <- predict(model, c("bus", "toilet"), type = "nearest")
#' nn
read.word2vec <- function(file){
    stopifnot(file.exists(file))
    w2v_load_model(file)
}

#' @export
summary.w2v <- function(object, type = "vocabulary", ...){
    type <- match.arg(type)
    if(type == "vocabulary"){
        w2v_dictionary(object$model)
    }else{
        stop("not implemented")
    }
}

#' @export
summary.w2v_trained <- function(object, type = "vocabulary", ...){
    summary.w2v(object = object, type = type, ...)
}

#' @export
predict.w2v <- function(object, newdata, type = c("nearest", "embedding"), ...){
    type <- match.arg(type)
    if(type == "embedding"){
        x <- w2v_embedding(object$model, x = newdata)
    }else if(type == "nearest"){
        x <- lapply(newdata, FUN=function(x){
            w2v_nearest(object$model, x = x, ...)    
        })
        names(x) <- newdata
    }
    x
}

#' @export
predict.w2v_trained <- function(object, newdata, type = c("nearest", "embedding"), ...){
    predict.w2v(object = object, newdata = newdata, type = type, ...)
}