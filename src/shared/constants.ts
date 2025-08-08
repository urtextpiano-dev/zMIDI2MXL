/**
 * Shared constants for MusicXML file validation and processing
 * 
 * Consolidates file extension and MIME type validation logic that was
 * previously duplicated across component, service, and main process.
 */

// MusicXML file extensions - single source of truth
export const MUSICXML_EXTENSIONS = ['.xml', '.musicxml', '.mxl'] as const;

// MusicXML MIME types for enhanced validation
export const MUSICXML_MIME_TYPES = [
  'application/vnd.recordare.musicxml+xml',
  'text/xml',
  'application/xml'
] as const;

// Type definitions for type safety
export type MusicXMLExtension = typeof MUSICXML_EXTENSIONS[number];
export type MusicXMLMimeType = typeof MUSICXML_MIME_TYPES[number];

/**
 * Extract file extension from filename, normalized to lowercase
 */
export const getFileExtension = (fileName: string): string => {
  return fileName.substring(fileName.lastIndexOf('.')).toLowerCase();
};

/**
 * Validate if a file is a supported MusicXML file based on extension and MIME type
 * 
 * @param file - File object to validate
 * @returns true if file is a valid MusicXML file
 */
export const isValidMusicXMLFile = (file: File): boolean => {
  const ext = getFileExtension(file.name);
  const hasValidExtension = MUSICXML_EXTENSIONS.includes(ext as MusicXMLExtension);
  const hasValidMimeType = MUSICXML_MIME_TYPES.includes(file.type as MusicXMLMimeType);
  
  // Accept file if either extension or MIME type is valid
  // This handles cases where browsers might not set MIME type correctly
  return hasValidExtension || hasValidMimeType;
};

/**
 * Validate file extension only (for cases where File object is not available)
 * 
 * @param fileName - Name of the file to validate
 * @returns true if file extension is supported
 */
export const isValidMusicXMLExtension = (fileName: string): boolean => {
  const ext = getFileExtension(fileName);
  return MUSICXML_EXTENSIONS.includes(ext as MusicXMLExtension);
};