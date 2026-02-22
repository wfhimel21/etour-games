// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ChessRulesModule
 * @dev Stateless chess rules engine for ChessOnChain
 * Contains all move validation, check detection, and game-end logic.
 * Called via delegatecall from ChessOnChain.
 *
 * Board packing: 64 squares x 4 bits = 256 bits (single uint256)
 * Piece encoding (4 bits):
 *   0x0 = Empty
 *   0x1 = White Pawn      0x7 = Black Pawn
 *   0x2 = White Knight    0x8 = Black Knight
 *   0x3 = White Bishop    0x9 = Black Bishop
 *   0x4 = White Rook      0xA = Black Rook
 *   0x5 = White Queen     0xB = Black Queen
 *   0x6 = White King      0xC = Black King
 */
contract ChessRulesModule {

    // ============ Constants ============

    uint8 public constant NO_EN_PASSANT = 63;  // Max 6-bit value (bits 0-5), not 64 which overlaps bit 6

    // Piece types
    uint8 public constant PIECE_NONE = 0;
    uint8 public constant PIECE_PAWN = 1;
    uint8 public constant PIECE_KNIGHT = 2;
    uint8 public constant PIECE_BISHOP = 3;
    uint8 public constant PIECE_ROOK = 4;
    uint8 public constant PIECE_QUEEN = 5;
    uint8 public constant PIECE_KING = 6;

    uint8 public constant BLACK_OFFSET = 6;

    // Packed piece values
    uint8 public constant WHITE_PAWN = 1;
    uint8 public constant WHITE_KNIGHT = 2;
    uint8 public constant WHITE_BISHOP = 3;
    uint8 public constant WHITE_ROOK = 4;
    uint8 public constant WHITE_QUEEN = 5;
    uint8 public constant WHITE_KING = 6;
    uint8 public constant BLACK_PAWN = 7;
    uint8 public constant BLACK_KNIGHT = 8;
    uint8 public constant BLACK_BISHOP = 9;
    uint8 public constant BLACK_ROOK = 10;
    uint8 public constant BLACK_QUEEN = 11;
    uint8 public constant BLACK_KING = 12;

    // State bit flags
    uint256 public constant EP_MASK = 0x3F;
    uint256 public constant WHITE_KING_MOVED = 1 << 6;
    uint256 public constant BLACK_KING_MOVED = 1 << 7;
    uint256 public constant WHITE_ROOK_A_MOVED = 1 << 8;
    uint256 public constant WHITE_ROOK_H_MOVED = 1 << 9;
    uint256 public constant BLACK_ROOK_A_MOVED = 1 << 10;
    uint256 public constant BLACK_ROOK_H_MOVED = 1 << 11;
    uint256 public constant WHITE_IN_CHECK = 1 << 12;
    uint256 public constant BLACK_IN_CHECK = 1 << 13;
    uint256 public constant HALF_MOVE_SHIFT = 14;
    uint256 public constant HALF_MOVE_MASK = 0xFF << HALF_MOVE_SHIFT;
    uint256 public constant FULL_MOVE_SHIFT = 22;
    uint256 public constant FULL_MOVE_MASK = 0x3FF << FULL_MOVE_SHIFT;

    // Initial positions
    uint256 public constant INITIAL_BOARD = 0xA89CB98A77777777000000000000000000000000000000001111111142365324;
    uint256 public constant INITIAL_STATE = NO_EN_PASSANT | (1 << FULL_MOVE_SHIFT);

    // ============ Board Helpers ============

    function getPiece(uint256 board, uint8 square) public pure returns (uint8) {
        return uint8((board >> (square * 4)) & 0xF);
    }

    function setPiece(uint256 board, uint8 square, uint8 piece) public pure returns (uint256) {
        uint256 mask = ~(uint256(0xF) << (square * 4));
        return (board & mask) | (uint256(piece) << (square * 4));
    }

    function isWhitePiece(uint8 piece) public pure returns (bool) {
        return piece >= 1 && piece <= 6;
    }

    function isBlackPiece(uint8 piece) public pure returns (bool) {
        return piece >= 7 && piece <= 12;
    }

    function getPieceType(uint8 piece) public pure returns (uint8) {
        if (piece == 0) return PIECE_NONE;
        if (piece <= 6) return piece;
        return piece - BLACK_OFFSET;
    }

    function isOwnPiece(uint8 piece, bool isWhite) public pure returns (bool) {
        if (isWhite) return isWhitePiece(piece);
        return isBlackPiece(piece);
    }

    function isEnemyPiece(uint8 piece, bool isWhite) public pure returns (bool) {
        if (piece == 0) return false;
        if (isWhite) return isBlackPiece(piece);
        return isWhitePiece(piece);
    }

    // ============ State Helpers ============

    function getEnPassantSquare(uint256 state) public pure returns (uint8) {
        return uint8(state & EP_MASK);
    }

    function setEnPassantSquare(uint256 state, uint8 square) public pure returns (uint256) {
        return (state & ~EP_MASK) | square;
    }

    function getHalfMoveClock(uint256 state) public pure returns (uint8) {
        return uint8((state & HALF_MOVE_MASK) >> HALF_MOVE_SHIFT);
    }

    function setHalfMoveClock(uint256 state, uint8 value) public pure returns (uint256) {
        return (state & ~HALF_MOVE_MASK) | (uint256(value) << HALF_MOVE_SHIFT);
    }

    function getFullMoveNumber(uint256 state) public pure returns (uint16) {
        return uint16((state & FULL_MOVE_MASK) >> FULL_MOVE_SHIFT);
    }

    function setFullMoveNumber(uint256 state, uint16 value) public pure returns (uint256) {
        return (state & ~FULL_MOVE_MASK) | (uint256(value) << FULL_MOVE_SHIFT);
    }

    function hasFlag(uint256 state, uint256 flag) public pure returns (bool) {
        return (state & flag) != 0;
    }

    function setFlag(uint256 state, uint256 flag) public pure returns (uint256) {
        return state | flag;
    }

    function clearFlag(uint256 state, uint256 flag) public pure returns (uint256) {
        return state & ~flag;
    }

    // ============ Move Validation ============

    function isValidMove(
        uint256 board,
        uint256 state,
        uint8 from,
        uint8 to,
        bool isWhite,
        uint8 promotion
    ) public pure returns (bool) {
        uint8 piece = getPiece(board, from);
        uint8 pieceType = getPieceType(piece);
        uint8 targetPiece = getPiece(board, to);

        // Cannot capture own piece
        if (isOwnPiece(targetPiece, isWhite)) return false;

        // Check piece-specific movement
        if (!_isPieceMovementValid(board, state, from, to, pieceType, isWhite)) return false;

        // Check if move leaves king in check
        if (_wouldLeaveKingInCheck(board, state, from, to, isWhite)) return false;

        // Validate promotion
        if (pieceType == PIECE_PAWN) {
            uint8 toRank = to / 8;
            bool isPromotion = (isWhite && toRank == 7) || (!isWhite && toRank == 0);
            if (isPromotion && (promotion < PIECE_KNIGHT || promotion > PIECE_QUEEN)) return false;
            if (!isPromotion && promotion != 0) return false;
        }

        return true;
    }

    function _isPieceMovementValid(
        uint256 board,
        uint256 state,
        uint8 from,
        uint8 to,
        uint8 pieceType,
        bool isWhite
    ) internal pure returns (bool) {
        int8 fromFile = int8(from % 8);
        int8 fromRank = int8(from / 8);
        int8 toFile = int8(to % 8);
        int8 toRank = int8(to / 8);
        int8 fileDiff = toFile - fromFile;
        int8 rankDiff = toRank - fromRank;

        if (pieceType == PIECE_PAWN) {
            return _isValidPawnMove(board, state, from, to, isWhite, fileDiff, rankDiff);
        } else if (pieceType == PIECE_KNIGHT) {
            return _isValidKnightMove(fileDiff, rankDiff);
        } else if (pieceType == PIECE_BISHOP) {
            return _isValidBishopMove(board, from, to, fileDiff, rankDiff);
        } else if (pieceType == PIECE_ROOK) {
            return _isValidRookMove(board, from, to, fileDiff, rankDiff);
        } else if (pieceType == PIECE_QUEEN) {
            return _isValidQueenMove(board, from, to, fileDiff, rankDiff);
        } else if (pieceType == PIECE_KING) {
            return _isValidKingMove(board, state, isWhite, fileDiff, rankDiff);
        }

        return false;
    }

    function _isValidPawnMove(
        uint256 board,
        uint256 state,
        uint8 from,
        uint8 to,
        bool isWhite,
        int8 fileDiff,
        int8 rankDiff
    ) internal pure returns (bool) {
        int8 direction = isWhite ? int8(1) : int8(-1);
        uint8 startRank = isWhite ? 1 : 6;

        // Forward move
        if (fileDiff == 0) {
            if (rankDiff == direction) {
                return getPiece(board, to) == 0;
            }
            if (rankDiff == 2 * direction && from / 8 == startRank) {
                uint8 intermediate = uint8(int8(from) + 8 * direction);
                return getPiece(board, to) == 0 && getPiece(board, intermediate) == 0;
            }
        }

        // Diagonal capture
        if ((fileDiff == 1 || fileDiff == -1) && rankDiff == direction) {
            uint8 targetPiece = getPiece(board, to);
            if (targetPiece != 0 && !isOwnPiece(targetPiece, isWhite)) {
                return true;
            }
            if (to == getEnPassantSquare(state)) {
                return true;
            }
        }

        return false;
    }

    function _isValidKnightMove(int8 fileDiff, int8 rankDiff) internal pure returns (bool) {
        int8 absFile = fileDiff < 0 ? -fileDiff : fileDiff;
        int8 absRank = rankDiff < 0 ? -rankDiff : rankDiff;
        return (absFile == 2 && absRank == 1) || (absFile == 1 && absRank == 2);
    }

    function _isValidBishopMove(uint256 board, uint8 from, uint8 to, int8 fileDiff, int8 rankDiff) internal pure returns (bool) {
        int8 absFile = fileDiff < 0 ? -fileDiff : fileDiff;
        int8 absRank = rankDiff < 0 ? -rankDiff : rankDiff;
        if (absFile != absRank) return false;
        return _isPathClear(board, from, to, fileDiff, rankDiff);
    }

    function _isValidRookMove(uint256 board, uint8 from, uint8 to, int8 fileDiff, int8 rankDiff) internal pure returns (bool) {
        if (fileDiff != 0 && rankDiff != 0) return false;
        return _isPathClear(board, from, to, fileDiff, rankDiff);
    }

    function _isValidQueenMove(uint256 board, uint8 from, uint8 to, int8 fileDiff, int8 rankDiff) internal pure returns (bool) {
        int8 absFile = fileDiff < 0 ? -fileDiff : fileDiff;
        int8 absRank = rankDiff < 0 ? -rankDiff : rankDiff;
        bool isDiagonal = (absFile == absRank);
        bool isStraight = (fileDiff == 0 || rankDiff == 0);
        if (!isDiagonal && !isStraight) return false;
        return _isPathClear(board, from, to, fileDiff, rankDiff);
    }

    function _isValidKingMove(
        uint256 board,
        uint256 state,
        bool isWhite,
        int8 fileDiff,
        int8 rankDiff
    ) internal pure returns (bool) {
        int8 absFile = fileDiff < 0 ? -fileDiff : fileDiff;
        int8 absRank = rankDiff < 0 ? -rankDiff : rankDiff;

        if (absFile <= 1 && absRank <= 1) return true;

        if (absRank == 0 && absFile == 2) {
            return _canCastle(board, state, isWhite, fileDiff > 0);
        }

        return false;
    }

    function _canCastle(uint256 board, uint256 state, bool isWhite, bool kingSide) internal pure returns (bool) {
        if (isWhite && hasFlag(state, WHITE_KING_MOVED)) return false;
        if (!isWhite && hasFlag(state, BLACK_KING_MOVED)) return false;

        if (isWhite) {
            if (kingSide && hasFlag(state, WHITE_ROOK_H_MOVED)) return false;
            if (!kingSide && hasFlag(state, WHITE_ROOK_A_MOVED)) return false;
            if (hasFlag(state, WHITE_IN_CHECK)) return false;
        } else {
            if (kingSide && hasFlag(state, BLACK_ROOK_H_MOVED)) return false;
            if (!kingSide && hasFlag(state, BLACK_ROOK_A_MOVED)) return false;
            if (hasFlag(state, BLACK_IN_CHECK)) return false;
        }

        uint8 kingSquare = isWhite ? 4 : 60;

        if (kingSide) {
            if (getPiece(board, kingSquare + 1) != 0) return false;
            if (getPiece(board, kingSquare + 2) != 0) return false;
            if (_isSquareAttacked(board, kingSquare + 1, isWhite)) return false;
            if (_isSquareAttacked(board, kingSquare + 2, isWhite)) return false;
        } else {
            if (getPiece(board, kingSquare - 1) != 0) return false;
            if (getPiece(board, kingSquare - 2) != 0) return false;
            if (getPiece(board, kingSquare - 3) != 0) return false;
            if (_isSquareAttacked(board, kingSquare - 1, isWhite)) return false;
            if (_isSquareAttacked(board, kingSquare - 2, isWhite)) return false;
        }

        return true;
    }

    function _isPathClear(uint256 board, uint8 from, uint8 to, int8 fileDiff, int8 rankDiff) internal pure returns (bool) {
        int8 fileStep = fileDiff == 0 ? int8(0) : (fileDiff > 0 ? int8(1) : int8(-1));
        int8 rankStep = rankDiff == 0 ? int8(0) : (rankDiff > 0 ? int8(1) : int8(-1));

        int8 currentFile = int8(from % 8) + fileStep;
        int8 currentRank = int8(from / 8) + rankStep;
        int8 targetFile = int8(to % 8);
        int8 targetRank = int8(to / 8);

        while (currentFile != targetFile || currentRank != targetRank) {
            uint8 currentSquare = uint8(currentRank * 8 + currentFile);
            if (getPiece(board, currentSquare) != 0) return false;
            currentFile += fileStep;
            currentRank += rankStep;
        }

        return true;
    }

    // ============ Check Detection ============

    function isKingInCheck(uint256 board, bool isWhite) public pure returns (bool) {
        uint8 kingSquare = _findKing(board, isWhite);
        return _isSquareAttacked(board, kingSquare, isWhite);
    }

    function _findKing(uint256 board, bool isWhite) internal pure returns (uint8) {
        uint8 king = isWhite ? WHITE_KING : BLACK_KING;
        for (uint8 i = 0; i < 64; i++) {
            if (getPiece(board, i) == king) return i;
        }
        revert("KNF");
    }

    function _isSquareAttacked(uint256 board, uint8 square, bool defendingIsWhite) internal pure returns (bool) {
        for (uint8 i = 0; i < 64; i++) {
            uint8 piece = getPiece(board, i);
            if (piece == 0) continue;
            if (isOwnPiece(piece, defendingIsWhite)) continue;

            if (_canPieceAttackSquare(board, i, square, piece)) return true;
        }
        return false;
    }

    function _canPieceAttackSquare(uint256 board, uint8 from, uint8 to, uint8 piece) internal pure returns (bool) {
        uint8 pieceType = getPieceType(piece);
        bool pIsWhite = isWhitePiece(piece);

        int8 fromFile = int8(from % 8);
        int8 fromRank = int8(from / 8);
        int8 toFile = int8(to % 8);
        int8 toRank = int8(to / 8);
        int8 fileDiff = toFile - fromFile;
        int8 rankDiff = toRank - fromRank;
        int8 absFile = fileDiff < 0 ? -fileDiff : fileDiff;
        int8 absRank = rankDiff < 0 ? -rankDiff : rankDiff;

        if (pieceType == PIECE_PAWN) {
            int8 direction = pIsWhite ? int8(1) : int8(-1);
            return (fileDiff == 1 || fileDiff == -1) && rankDiff == direction;
        } else if (pieceType == PIECE_KNIGHT) {
            return (absFile == 2 && absRank == 1) || (absFile == 1 && absRank == 2);
        } else if (pieceType == PIECE_BISHOP) {
            if (absFile != absRank) return false;
            return _isPathClear(board, from, to, fileDiff, rankDiff);
        } else if (pieceType == PIECE_ROOK) {
            if (fileDiff != 0 && rankDiff != 0) return false;
            return _isPathClear(board, from, to, fileDiff, rankDiff);
        } else if (pieceType == PIECE_QUEEN) {
            bool isDiagonal = (absFile == absRank);
            bool isStraight = (fileDiff == 0 || rankDiff == 0);
            if (!isDiagonal && !isStraight) return false;
            return _isPathClear(board, from, to, fileDiff, rankDiff);
        } else if (pieceType == PIECE_KING) {
            return absFile <= 1 && absRank <= 1;
        }

        return false;
    }

    function _wouldLeaveKingInCheck(uint256 board, uint256 state, uint8 from, uint8 to, bool isWhite) internal pure returns (bool) {
        uint256 tempBoard = board;
        uint8 piece = getPiece(tempBoard, from);

        tempBoard = setPiece(tempBoard, to, piece);
        tempBoard = setPiece(tempBoard, from, 0);

        uint8 pieceType = getPieceType(piece);
        uint8 epSquare = getEnPassantSquare(state);
        if (pieceType == PIECE_PAWN && to == epSquare && epSquare != NO_EN_PASSANT) {
            uint8 capturedPawnSquare = isWhite ? to - 8 : to + 8;
            tempBoard = setPiece(tempBoard, capturedPawnSquare, 0);
        }

        return isKingInCheck(tempBoard, isWhite);
    }

    // ============ Legal Move Detection ============

    function hasLegalMoves(uint256 board, uint256 state, bool isWhite) public pure returns (bool) {
        for (uint8 from = 0; from < 64; from++) {
            uint8 piece = getPiece(board, from);
            if (piece == 0) continue;
            if (!isOwnPiece(piece, isWhite)) continue;

            for (uint8 to = 0; to < 64; to++) {
                if (from == to) continue;
                if (isValidMove(board, state, from, to, isWhite, 0)) return true;
                if (getPieceType(piece) == PIECE_PAWN) {
                    uint8 toRank = to / 8;
                    if ((isWhite && toRank == 7) || (!isWhite && toRank == 0)) {
                        if (isValidMove(board, state, from, to, isWhite, PIECE_QUEEN)) return true;
                    }
                }
            }
        }
        return false;
    }

    // ============ Draw Detection ============

    function isInsufficientMaterial(uint256 board) public pure returns (bool) {
        uint8 whitePieceCount = 0;
        uint8 blackPieceCount = 0;
        bool whiteBishop = false;
        bool blackBishop = false;
        bool whiteKnight = false;
        bool blackKnight = false;

        for (uint8 i = 0; i < 64; i++) {
            uint8 piece = getPiece(board, i);
            if (piece == 0) continue;

            uint8 pieceType = getPieceType(piece);

            if (pieceType == PIECE_PAWN || pieceType == PIECE_ROOK || pieceType == PIECE_QUEEN) {
                return false;
            }

            if (isWhitePiece(piece)) {
                if (pieceType != PIECE_KING) whitePieceCount++;
                if (pieceType == PIECE_BISHOP) whiteBishop = true;
                if (pieceType == PIECE_KNIGHT) whiteKnight = true;
            } else {
                if (pieceType != PIECE_KING) blackPieceCount++;
                if (pieceType == PIECE_BISHOP) blackBishop = true;
                if (pieceType == PIECE_KNIGHT) blackKnight = true;
            }
        }

        if (whitePieceCount == 0 && blackPieceCount == 0) return true;
        if (whitePieceCount == 0 && blackPieceCount == 1 && (blackBishop || blackKnight)) return true;
        if (blackPieceCount == 0 && whitePieceCount == 1 && (whiteBishop || whiteKnight)) return true;
        if (whitePieceCount == 1 && blackPieceCount == 1 && whiteBishop && blackBishop) return true;

        return false;
    }

    // ============ Move Execution Helpers ============

    /**
     * @dev Execute a move and return the updated board and state
     * This is a pure function that computes the new game state
     */
    function executeMove(
        uint256 board,
        uint256 state,
        uint8 from,
        uint8 to,
        uint8 promotion,
        bool isWhite
    ) public pure returns (
        uint256 newBoard,
        uint256 newState,
        bool isCapture,
        bool isPawnMove,
        uint8 capturedEnPassantSquare
    ) {
        newBoard = board;
        newState = state;
        capturedEnPassantSquare = 0;

        uint8 piece = getPiece(board, from);
        uint8 pieceType = getPieceType(piece);
        uint8 capturedPiece = getPiece(board, to);
        isCapture = capturedPiece != 0;
        isPawnMove = pieceType == PIECE_PAWN;

        // Handle en passant capture
        uint8 epSquare = getEnPassantSquare(state);
        if (isPawnMove && to == epSquare && epSquare != NO_EN_PASSANT) {
            capturedEnPassantSquare = isWhite ? to - 8 : to + 8;
            newBoard = setPiece(newBoard, capturedEnPassantSquare, 0);
            isCapture = true;
        }

        // Clear en passant
        newState = setEnPassantSquare(newState, NO_EN_PASSANT);

        // Set new en passant if double pawn push
        if (isPawnMove) {
            int8 rankDiff = int8(to / 8) - int8(from / 8);
            if (rankDiff == 2 || rankDiff == -2) {
                newState = setEnPassantSquare(newState, (from + to) / 2);
            }
        }

        // Handle castling
        if (pieceType == PIECE_KING) {
            int8 fileDiff = int8(to % 8) - int8(from % 8);
            if (fileDiff == 2 || fileDiff == -2) {
                bool kingSide = fileDiff > 0;
                uint8 rookFrom;
                uint8 rookTo;

                if (isWhite) {
                    rookFrom = kingSide ? 7 : 0;
                    rookTo = kingSide ? 5 : 3;
                } else {
                    rookFrom = kingSide ? 63 : 56;
                    rookTo = kingSide ? 61 : 59;
                }

                newBoard = setPiece(newBoard, rookTo, getPiece(newBoard, rookFrom));
                newBoard = setPiece(newBoard, rookFrom, 0);
            }

            newState = setFlag(newState, isWhite ? WHITE_KING_MOVED : BLACK_KING_MOVED);
        }

        // Track rook movement
        if (pieceType == PIECE_ROOK) {
            if (from == 0) newState = setFlag(newState, WHITE_ROOK_A_MOVED);
            else if (from == 7) newState = setFlag(newState, WHITE_ROOK_H_MOVED);
            else if (from == 56) newState = setFlag(newState, BLACK_ROOK_A_MOVED);
            else if (from == 63) newState = setFlag(newState, BLACK_ROOK_H_MOVED);
        }

        // Track captured rooks
        if (to == 0 && capturedPiece == WHITE_ROOK) newState = setFlag(newState, WHITE_ROOK_A_MOVED);
        else if (to == 7 && capturedPiece == WHITE_ROOK) newState = setFlag(newState, WHITE_ROOK_H_MOVED);
        else if (to == 56 && capturedPiece == BLACK_ROOK) newState = setFlag(newState, BLACK_ROOK_A_MOVED);
        else if (to == 63 && capturedPiece == BLACK_ROOK) newState = setFlag(newState, BLACK_ROOK_H_MOVED);

        // Execute basic move
        newBoard = setPiece(newBoard, to, piece);
        newBoard = setPiece(newBoard, from, 0);

        // Handle pawn promotion
        if (isPawnMove) {
            uint8 toRank = to / 8;
            if ((isWhite && toRank == 7) || (!isWhite && toRank == 0)) {
                uint8 newPiece = isWhite ? promotion : promotion + BLACK_OFFSET;
                newBoard = setPiece(newBoard, to, newPiece);
            }
        }

        // Update half-move clock
        if (isCapture || isPawnMove) {
            newState = setHalfMoveClock(newState, 0);
        } else {
            newState = setHalfMoveClock(newState, getHalfMoveClock(newState) + 1);
        }

        // Update full move number
        if (!isWhite) {
            newState = setFullMoveNumber(newState, getFullMoveNumber(newState) + 1);
        }

        // Update check status
        newState = clearFlag(newState, isWhite ? WHITE_IN_CHECK : BLACK_IN_CHECK);

        bool opponentInCheck = isKingInCheck(newBoard, !isWhite);
        if (opponentInCheck) {
            newState = setFlag(newState, isWhite ? BLACK_IN_CHECK : WHITE_IN_CHECK);
        } else {
            newState = clearFlag(newState, isWhite ? BLACK_IN_CHECK : WHITE_IN_CHECK);
        }
    }

    /**
     * @dev Combined function: validate move, execute it, and determine game result
     * Returns gameEnd: 0=ongoing, 1=checkmate, 2=stalemate, 3=fifty-move, 4=insufficient
     * This reduces external calls from 4-5 to just 1
     */
    function processMove(
        uint256 board, uint256 state, uint8 from, uint8 to, uint8 promotion, bool isWhite
    ) public pure returns (bool valid, uint256 newBoard, uint256 newState, uint8 gameEnd) {
        if (!isValidMove(board, state, from, to, isWhite, promotion)) {
            return (false, 0, 0, 0);
        }

        (newBoard, newState,,,) = executeMove(board, state, from, to, promotion, isWhite);
        valid = true;

        bool oppInCheck = isKingInCheck(newBoard, !isWhite);
        bool oppHasMoves = hasLegalMoves(newBoard, newState, !isWhite);

        if (oppInCheck && !oppHasMoves) {
            gameEnd = 1; // checkmate
        } else if (!oppInCheck && !oppHasMoves) {
            gameEnd = 2; // stalemate
        } else if (getHalfMoveClock(newState) >= 100) {
            gameEnd = 3; // fifty-move rule
        } else if (isInsufficientMaterial(newBoard)) {
            gameEnd = 4; // insufficient material
        }
        // gameEnd = 0 means ongoing
    }
}
