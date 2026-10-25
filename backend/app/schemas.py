from pydantic import BaseModel, EmailStr
from typing import Optional, List


class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    password: str
    phone: Optional[str] = None
    role: str  # 'user' | 'coach'
    goal: Optional[str] = "maintain"
    weightKg: Optional[float] = None
    goalWeightKg: Optional[float] = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    role: Optional[str] = None


class PrescriptionRequest(BaseModel):
    proteinG: float
    carbsG: float
    fatG: float
    calories: float


class GroceryItemRequest(BaseModel):
    name: str
    emoji: Optional[str] = "🛒"
    category: Optional[str] = "Other"
    amount: Optional[float] = None
    unit: Optional[str] = "g"


class GroceryToggleRequest(BaseModel):
    checked: bool


class ReminderToggleRequest(BaseModel):
    enabled: bool


class ReminderBulkSaveRequest(BaseModel):
    reminders: List[dict]  # [{id, enabled}, ...]


class MealContextRequest(BaseModel):
    mealType: str = "Lunch"          # Breakfast | Lunch | Dinner | Supper | Other
    futureMeal: str = "not_sure"     # yes | no | not_sure


class IngredientAmount(BaseModel):
    name: str
    amount: float                    # grams (or ml for liquids)


class MealRecordRequest(BaseModel):
    """Used both to save a planned meal and to confirm a consumed one."""
    recipeId: str
    mealType: str = "Lunch"
    futureMeal: Optional[str] = None
    ingredients: Optional[List[IngredientAmount]] = None   # ingredient-level recipes
    portionFactor: Optional[float] = None                  # recipes without ingredient data
    requestId: Optional[str] = None                        # same id sent twice = one record
    plannedId: Optional[str] = None                        # promote a planned meal to consumed


class MealEditRequest(BaseModel):
    ingredients: Optional[List[IngredientAmount]] = None
    portionFactor: Optional[float] = None
    grams: Optional[float] = None                          # single foods logged by weight
    mealType: Optional[str] = None


class AddClientRequest(BaseModel):
    email: EmailStr


class CoachNoteRequest(BaseModel):
    note: str


class MessageRequest(BaseModel):
    text: str


class MealPhotoRequest(BaseModel):
    mealLogId: str
    imageBase64: str
    source: str = "camera"           # the app only ever sends "camera"; anything else is rejected
    capturedAt: Optional[str] = None  # ISO-8601 time the shutter was pressed


class ProfileUpdateRequest(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    goal: Optional[str] = None
    weightKg: Optional[float] = None
    goalWeightKg: Optional[float] = None


class NotificationPrefsRequest(BaseModel):
    push: Optional[bool] = None       # master switch
    targets: Optional[bool] = None    # coach updated my targets
    notes: Optional[bool] = None      # coach left a note
    chat: Optional[bool] = None       # new chat message
    mission: Optional[bool] = None    # mission results


class FoodLogRequest(BaseModel):
    name: str
    grams: float
    mealType: Optional[str] = "Meal"
    source: str = "custom"  # "USDA" | "Open Food Facts" | "custom"
    # Nutrients per 100 g of this food (for "custom" foods the user types these in).
    caloriesPer100g: float
    proteinPer100g: float
    carbsPer100g: float
    fatPer100g: float
    requestId: Optional[str] = None


class AvatarRequest(BaseModel):
    imageBase64: str
